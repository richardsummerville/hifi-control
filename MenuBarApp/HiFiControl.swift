import AppKit
import Darwin
import Foundation
import ServiceManagement

// MARK: - Device Discovery

class DeviceDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = DeviceDiscovery()

    var cxnHost: String = "192.168.x.x"
    var tvHost: String = "192.168.x.x"
    let tvMAC = "XX:XX:XX:XX:XX:XX"

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var resolved = false

    func discover() {
        // mDNS browse for CXN
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_http._tcp.", inDomain: "local.")

        // Resolve TV IP from ARP table by MAC
        resolveTVFromARP()

        // Stop browsing after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.browser?.stop()
        }
    }

    private func resolveTVFromARP() {
        DispatchQueue.global().async { [self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
            process.arguments = ["-a"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: "\n") {
                    if line.lowercased().contains(self.tvMAC) {
                        // Extract IP from "(192.168.x.x)"
                        if let start = line.firstIndex(of: "("),
                           let end = line.firstIndex(of: ")") {
                            let ip = String(line[line.index(after: start)..<end])
                            DispatchQueue.main.async {
                                if self.tvHost != ip {
                                    print("TV discovered at \(ip)")
                                    self.tvHost = ip
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if service.name == "CXN Streamer" {
            services.append(service)
            service.delegate = self
            service.resolve(withTimeout: 5)
        }
    }

    // NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        for addrData in addresses {
            addrData.withUnsafeBytes { ptr in
                guard let sockAddr = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
                if sockAddr.pointee.sa_family == sa_family_t(AF_INET) {
                    let ipv4 = sockAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    let ip = String(cString: inet_ntoa(ipv4.sin_addr))
                    if self.cxnHost != ip {
                        print("CXN discovered at \(ip)")
                        self.cxnHost = ip
                    }
                }
            }
        }
    }
}

// MARK: - Settings

class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set {
            defaults.set(newValue, forKey: "launchAtLogin")
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Login item error: \(error)")
                }
            }
        }
    }
}

// MARK: - CXN v2 WebSocket Control

class CXNController {
    var host: String { DeviceDiscovery.shared.cxnHost }

    func sendPower(_ on: Bool, completion: @escaping (Bool) -> Void) {
        let url = URL(string: "ws://\(host):80/smoip")!
        var request = URLRequest(url: url)
        request.setValue("ws://\(host)", forHTTPHeaderField: "Origin")
        request.setValue("\(host):80", forHTTPHeaderField: "Host")

        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()

        let payload: [String: Any] = [
            "path": "/zone/state",
            "params": ["power": on]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            completion(false)
            return
        }

        task.send(.string(json)) { error in
            if let error = error {
                print("CXN send error: \(error)")
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                task.cancel(with: .goingAway, reason: nil)
                completion(true)
            }
        }
    }

    func getState(completion: @escaping (Bool?, Int?, String?) -> Void) {
        let url = URL(string: "http://\(host)/smoip/zone/state")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let zoneData = json["data"] as? [String: Any] else {
                completion(nil, nil, nil)
                return
            }
            let power = zoneData["power"] as? Bool
            let volume = zoneData["volume_percent"] as? Int
            let source = zoneData["source"] as? String
            completion(power, volume, source)
        }.resume()
    }

    func powerCycle(completion: @escaping (Bool) -> Void) {
        sendPower(false) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.sendPower(true) { success in
                    completion(success)
                }
            }
        }
    }
}

// MARK: - LG TV WebSocket Control

class LGTVController {
    var host: String { DeviceDiscovery.shared.tvHost }
    private var clientKey: String?

    init() {
        // Load saved client key from lgtv2 (persist-path location)
        // Try all keyfiles in the directory since IP may change
        let dir = NSString(string: "~/Library/Preferences/lgtv2").expandingTildeInPath
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir) {
            for file in files where file.hasPrefix("keyfile-") {
                let path = (dir as NSString).appendingPathComponent(file)
                if let key = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                   !key.isEmpty {
                    clientKey = key
                    break
                }
            }
        }
    }

    func sendCommand(_ uri: String, completion: @escaping (Bool) -> Void) {
        let url = URL(string: "ws://\(host):3000")!
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        // Register with client key
        let regPayload: [String: Any] = [
            "type": "register",
            "id": "register_0",
            "payload": clientKey != nil ? ["client-key": clientKey!] : [:]
        ]

        guard let regData = try? JSONSerialization.data(withJSONObject: regPayload),
              let regJson = String(data: regData, encoding: .utf8) else {
            completion(false)
            return
        }

        task.send(.string(regJson)) { error in
            if let error = error {
                print("LG TV register error: \(error)")
                completion(false)
                return
            }

            // Wait for registration response, then send command
            task.receive { result in
                // Send the actual command
                let cmdPayload: [String: Any] = [
                    "type": "request",
                    "id": "cmd_1",
                    "uri": uri
                ]

                guard let cmdData = try? JSONSerialization.data(withJSONObject: cmdPayload),
                      let cmdJson = String(data: cmdData, encoding: .utf8) else {
                    completion(false)
                    return
                }

                task.send(.string(cmdJson)) { error in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        task.cancel(with: .goingAway, reason: nil)
                        completion(error == nil)
                    }
                }
            }
        }
    }

    // Track local state after explicit power off
    var knownOff = false

    func getState(completion: @escaping (Bool?) -> Void) {
        if knownOff {
            completion(false)
            return
        }
        // Try a real SSAP query — if the TV is off/standby, the WebSocket will fail to register
        let url = URL(string: "ws://\(host):3000")!
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        let regPayload: [String: Any] = [
            "type": "register",
            "id": "reg_poll",
            "payload": clientKey != nil ? ["client-key": clientKey!] : [:]
        ]

        guard let regData = try? JSONSerialization.data(withJSONObject: regPayload),
              let regJson = String(data: regData, encoding: .utf8) else {
            completion(nil)
            return
        }

        let timeout = DispatchWorkItem {
            task.cancel(with: .goingAway, reason: nil)
            completion(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)

        task.send(.string(regJson)) { error in
            if error != nil {
                timeout.cancel()
                task.cancel(with: .goingAway, reason: nil)
                completion(nil)
                return
            }
            task.receive { result in
                timeout.cancel()
                switch result {
                case .success(let msg):
                    if case .string(let text) = msg, text.contains("registered") {
                        completion(true)
                    } else {
                        completion(nil)
                    }
                case .failure:
                    completion(nil)
                }
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    func powerOff(completion: @escaping (Bool) -> Void) {
        sendCommand("ssap://system/turnOff") { [weak self] success in
            if success { self?.knownOff = true }
            completion(success)
        }
    }

    func powerOn(completion: @escaping (Bool) -> Void) {
        // Wake-on-LAN magic packet
        let macBytes: [UInt8] = [0x20, 0x28, 0xBC, 0x1A, 0x59, 0xFE]
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }

        let data = Data(packet)
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { completion(false); return }

        var broadcastEnable: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))

        let targets = ["192.168.0.255", "255.255.255.255", host]
        var sent: Int = 0
        for target in targets {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(9).bigEndian
            addr.sin_addr.s_addr = inet_addr(target)

            sent += data.withUnsafeBytes { ptr in
                withUnsafePointer(to: &addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                        sendto(sock, ptr.baseAddress, ptr.count, 0, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        close(sock)
        knownOff = false
        completion(sent > 0)
    }
}

// MARK: - NVIDIA Shield Status

class ShieldController {
    let host = "192.168.x.x"

    func getState(completion: @escaping (Bool?) -> Void) {
        let url = URL(string: "http://\(host):8008/setup/eureka_info?params=name")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["name"] != nil {
                completion(true)
            } else {
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - Toggle Row View

class ToggleRowView: NSView {
    let toggle = NSSwitch()
    let label = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    let iconView = NSImageView()
    var onToggle: ((Bool) -> Void)?

    init(title: String, icon: String, width: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 44))

        // Icon
        let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        iconView.image = img?.withSymbolConfiguration(config)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.frame = NSRect(x: 16, y: 12, width: 20, height: 20)
        addSubview(iconView)

        // Title
        label.stringValue = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.frame = NSRect(x: 44, y: 22, width: 160, height: 16)
        addSubview(label)

        // Status subtitle
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 44, y: 6, width: 160, height: 14)
        addSubview(statusLabel)

        // Toggle
        toggle.controlSize = .mini
        toggle.frame = NSRect(x: width - 52, y: 12, width: 36, height: 20)
        toggle.target = self
        toggle.action = #selector(toggled)
        addSubview(toggle)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc func toggled() {
        onToggle?(toggle.state == .on)
    }

    func setState(_ on: Bool) {
        toggle.state = on ? .on : .off
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func setEnabled(_ enabled: Bool) {
        toggle.isEnabled = enabled
    }
}

// MARK: - Status Row View (no toggle, display only)

class StatusRowView: NSView {
    let label = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    let iconView = NSImageView()
    let dot = NSTextField(labelWithString: "")

    init(title: String, icon: String, isOn: Bool?, width: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 44))

        let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        iconView.image = img?.withSymbolConfiguration(config)
        iconView.contentTintColor = isOn == true ? .systemGreen : .secondaryLabelColor
        iconView.frame = NSRect(x: 16, y: 12, width: 20, height: 20)
        addSubview(iconView)

        label.stringValue = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.frame = NSRect(x: 44, y: 22, width: 160, height: 16)
        addSubview(label)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 44, y: 6, width: 160, height: 14)
        addSubview(statusLabel)

        // Status dot on the right
        dot.font = .systemFont(ofSize: 10)
        dot.textColor = isOn == true ? .systemGreen : isOn == false ? .secondaryLabelColor : .tertiaryLabelColor
        dot.stringValue = isOn == true ? "●" : "●"
        dot.alignment = .right
        dot.frame = NSRect(x: width - 40, y: 14, width: 20, height: 16)
        addSubview(dot)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Header View

class HeaderView: NSView {
    let titleLabel = NSTextField(labelWithString: "")

    init(title: String, width: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 28))

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.frame = NSRect(x: 16, y: 4, width: 200, height: 16)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Menu Bar App

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let cxn = CXNController()
    let tv = LGTVController()
    let shield = ShieldController()
    var cxnPowerState: Bool?
    var tvPowerState: Bool?
    var shieldPowerState: Bool?
    var roonRunning: Bool = false
    var statusTimer: Timer?
    var cxnToggle: ToggleRowView!
    var tvToggle: ToggleRowView!
    var roonToggle: ToggleRowView!
    var busyLock = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "hifispeaker.2.fill",
                                accessibilityDescription: "HiFi Control")
            image?.isTemplate = true
            button.image = image
        }

        DeviceDiscovery.shared.discover()
        buildMenu()
        pollState()

        statusTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.pollState()
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.minimumWidth = 280

        // ── DEVICES ──
        let devicesHeader = NSMenuItem()
        devicesHeader.view = HeaderView(title: "DEVICES")
        menu.addItem(devicesHeader)

        // CXN Toggle
        cxnToggle = ToggleRowView(title: "CXN v2", icon: "hifispeaker.fill")
        cxnToggle.setState(cxnPowerState == true)
        cxnToggle.setStatus(cxnPowerState == true ? "On  ·  Roon Ready" : cxnPowerState == false ? "Standby" : "Unreachable")
        cxnToggle.iconView.contentTintColor = cxnPowerState == true ? .controlAccentColor : .secondaryLabelColor
        cxnToggle.onToggle = { [weak self] on in
            self?.toggleCXN(on)
        }
        let cxnItem = NSMenuItem()
        cxnItem.view = cxnToggle
        menu.addItem(cxnItem)

        // LG TV Toggle
        tvToggle = ToggleRowView(title: "LG OLED", icon: "tv.fill")
        tvToggle.setState(tvPowerState == true)
        tvToggle.setStatus(tvPowerState == true ? "On" : "Off / Standby")
        tvToggle.iconView.contentTintColor = tvPowerState == true ? .controlAccentColor : .secondaryLabelColor
        tvToggle.onToggle = { [weak self] on in
            self?.toggleTV(on)
        }
        let tvItem = NSMenuItem()
        tvItem.view = tvToggle
        menu.addItem(tvItem)

        // Shield Status (display only — controlled via CEC from TV)
        let shieldRow = StatusRowView(title: "NVIDIA Shield", icon: "gamecontroller.fill", isOn: shieldPowerState)
        shieldRow.statusLabel.stringValue = shieldPowerState == true ? "On  ·  via HDMI-CEC" : "Off"
        let shieldItem = NSMenuItem()
        shieldItem.view = shieldRow
        menu.addItem(shieldItem)

        menu.addItem(NSMenuItem.separator())

        // ── SESSIONS ──
        let sessionsHeader = NSMenuItem()
        sessionsHeader.view = HeaderView(title: "SESSIONS")
        menu.addItem(sessionsHeader)

        // Roon Toggle
        roonRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.roonlabs.Roon" || $0.localizedName == "Roon"
        }
        roonToggle = ToggleRowView(title: "Roon", icon: "music.note")
        roonToggle.setState(roonRunning)
        roonToggle.setStatus(roonRunning ? "Running" : "Stopped")
        roonToggle.iconView.contentTintColor = roonRunning ? .systemPurple : .secondaryLabelColor
        roonToggle.onToggle = { [weak self] on in
            self?.toggleRoon(on)
        }
        let roonItem = NSMenuItem()
        roonItem.view = roonToggle
        menu.addItem(roonItem)

        menu.addItem(NSMenuItem.separator())

        // ── SETTINGS ──
        let settingsMenu = NSMenu()
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = Settings.shared.launchAtLogin ? .on : .off
        settingsMenu.addItem(launchItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    func pollState() {
        guard !busyLock else { return }

        let group = DispatchGroup()

        group.enter()
        cxn.getState { [weak self] power, volume, source in
            DispatchQueue.main.async {
                self?.cxnPowerState = power
                group.leave()
            }
        }

        group.enter()
        tv.getState { [weak self] power in
            DispatchQueue.main.async {
                if power == true { self?.tv.knownOff = false }
                self?.tvPowerState = power
                group.leave()
            }
        }

        group.enter()
        // Shield follows TV via HDMI-CEC — mirror TV state
        DispatchQueue.main.async { [weak self] in
            self?.shieldPowerState = self?.tvPowerState
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.buildMenu()
        }
    }

    func toggleCXN(_ on: Bool) {
        guard !busyLock else { return }
        busyLock = true
        cxnToggle.setStatus(on ? "Powering on…" : "Powering off…")
        cxnToggle.setEnabled(false)

        if on {
            cxn.powerCycle { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.busyLock = false
                    self?.pollState()
                }
            }
        } else {
            cxn.sendPower(false) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.busyLock = false
                    self?.pollState()
                }
            }
        }
    }

    func toggleTV(_ on: Bool) {
        guard !busyLock else { return }
        busyLock = true
        tvToggle.setStatus(on ? "Waking up…" : "Turning off…")
        tvToggle.setEnabled(false)

        if on {
            tv.powerOn { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.busyLock = false
                    self?.pollState()
                }
            }
        } else {
            tv.powerOff { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.busyLock = false
                    self?.pollState()
                }
            }
        }
    }

    func toggleRoon(_ on: Bool) {
        guard !busyLock else { return }
        busyLock = true
        roonToggle.setStatus(on ? "Starting…" : "Stopping…")
        roonToggle.setEnabled(false)

        if on {
            cxnToggle.setStatus("Powering on…")
            cxn.powerCycle { [weak self] _ in
                DispatchQueue.main.async {
                    let url = URL(fileURLWithPath: "/Applications/Roon.app")
                    NSWorkspace.shared.openApplication(at: url,
                                                       configuration: NSWorkspace.OpenConfiguration())
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.busyLock = false
                        self?.pollState()
                    }
                }
            }
        } else {
            for app in NSWorkspace.shared.runningApplications {
                if app.bundleIdentifier == "com.roonlabs.Roon" ||
                   app.localizedName == "Roon" {
                    app.terminate()
                }
            }
            cxnToggle.setStatus("Powering off…")
            cxn.sendPower(false) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.busyLock = false
                    self?.pollState()
                }
            }
        }
    }

    @objc func toggleLaunchAtLogin() {
        Settings.shared.launchAtLogin.toggle()
        buildMenu()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
