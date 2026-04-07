import AppKit
import Darwin
import Foundation
import ServiceManagement

// MARK: - Device Discovery

class DeviceDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = DeviceDiscovery()

    // Default IPs — override via mDNS discovery or DHCP reservation
    var cxnHost: String = "192.168.x.x"
    var tvHost: String = "192.168.x.x"
    var tvMAC: String = ""
    var shieldHost: String = "192.168.x.x"
    var xboxHost: String = "192.168.x.x"
    var plexHost: String = "192.168.x.x"
    var plexToken: String = ""
    var imacHost: String = "192.168.x.x"

    override init() {
        super.init()
        loadConfig()
    }

    private func loadConfig() {
        // Read config.local from app bundle's parent or working directory
        let paths = [
            NSString(string: "~/Documents/Projects/home-control/config.local").expandingTildeInPath,
            "config.local"
        ]
        for path in paths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let val = parts[1].trimmingCharacters(in: .whitespaces)
                switch key {
                case "TV_MAC": tvMAC = val
                case "CXN_IP": cxnHost = val
                case "TV_IP": tvHost = val
                case "SHIELD_IP": shieldHost = val
                case "XBOX_IP": xboxHost = val
                case "PLEX_IP": plexHost = val
                case "PLEX_TOKEN": plexToken = val
                case "IMAC_IP": imacHost = val
                default: break
                }
            }
            break
        }
    }

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
        guard !tvMAC.isEmpty else { return }
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

// MARK: - Shield App Registry

struct ShieldApp {
    let name: String
    let package: String
    let iconFile: String?       // PNG filename (without extension) in icons/
    let iconFallback: String    // SF Symbol fallback
    var iconColor: NSColor?     // Tint for SF Symbol fallback
}

let shieldAppRegistry: [ShieldApp] = [
    ShieldApp(name: "Plex", package: "com.plexapp.android", iconFile: "plex", iconFallback: "film.fill"),
    ShieldApp(name: "Plexamp", package: "tv.plex.labs.plexamp", iconFile: "plexamp", iconFallback: "waveform"),
    ShieldApp(name: "Netflix", package: "com.netflix.ninja", iconFile: "netflix", iconFallback: "play.rectangle.fill"),
    ShieldApp(name: "Disney+", package: "com.disney.disneyplus", iconFile: "disney", iconFallback: "sparkles"),
    ShieldApp(name: "Apple TV", package: "com.apple.atve.androidtv.appletv", iconFile: "appletv", iconFallback: "appletv.fill"),
    ShieldApp(name: "Amazon Prime", package: "com.amazon.amazonvideo.livingroom", iconFile: "prime", iconFallback: "shippingbox.fill"),
    ShieldApp(name: "YouTube", package: "com.google.android.youtube.tv", iconFile: nil, iconFallback: "play.rectangle.fill", iconColor: .systemRed),
    ShieldApp(name: "Stremio", package: "com.stremio.one", iconFile: "stremio", iconFallback: "popcorn.fill"),
    ShieldApp(name: "MUBI", package: "com.mubi", iconFile: "mubi", iconFallback: "film.stack.fill"),
    ShieldApp(name: "BBC iPlayer", package: "com.nvidia.bbciplayer", iconFile: "bbc", iconFallback: "play.tv.fill"),
    ShieldApp(name: "ITV", package: "air.ITVMobilePlayer", iconFile: "itv", iconFallback: "play.tv.fill"),
    ShieldApp(name: "Channel 4", package: "com.channel4.ondemand", iconFile: "channel4", iconFallback: "play.tv.fill"),
    ShieldApp(name: "Tidal", package: "com.aspiro.tidal", iconFile: "tidal", iconFallback: "music.note"),
    ShieldApp(name: "VLC", package: "org.videolan.vlc", iconFile: "vlc", iconFallback: "play.circle.fill"),
    ShieldApp(name: "RetroArch", package: "retrobox.v2.retroarch", iconFile: "retroarch", iconFallback: "gamecontroller.fill"),
    ShieldApp(name: "My5", package: "com.channel5.my5", iconFile: "my5", iconFallback: "play.tv.fill"),
]

func loadAppIcon(_ app: ShieldApp, size: CGFloat = 16) -> NSImage? {
    if let file = app.iconFile {
        let paths = [
            NSString(string: "~/Documents/Projects/home-control/MenuBarApp/icons/\(file).png").expandingTildeInPath,
            "icons/\(file).png"
        ]
        for path in paths {
            if let img = NSImage(contentsOfFile: path) {
                img.size = NSSize(width: size, height: size)
                return img
            }
        }
    }
    let config = NSImage.SymbolConfiguration(pointSize: size - 3, weight: .medium)
    let img = NSImage(systemSymbolName: app.iconFallback, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    if let color = app.iconColor, let img = img {
        let tinted = NSImage(size: img.size, flipped: false) { rect in
            img.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
    return img
}

// MARK: - Settings

class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    func isServiceEnabled(_ package: String) -> Bool {
        // Default all to enabled if never set
        if defaults.object(forKey: "service_\(package)") == nil { return true }
        return defaults.bool(forKey: "service_\(package)")
    }

    func setServiceEnabled(_ package: String, enabled: Bool) {
        defaults.set(enabled, forKey: "service_\(package)")
    }

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

        var completed = false
        let finish: (Bool?) -> Void = { result in
            guard !completed else { return }
            completed = true
            task.cancel(with: .goingAway, reason: nil)
            completion(result)
        }

        let timeout = DispatchWorkItem { finish(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)

        task.send(.string(regJson)) { error in
            if error != nil {
                timeout.cancel()
                finish(nil)
                return
            }
            // LG SSAP sends multiple messages (hello, then registration response)
            // Read up to 5 messages looking for the "registered" confirmation
            func readNext(_ remaining: Int) {
                guard remaining > 0 else {
                    timeout.cancel()
                    finish(nil)
                    return
                }
                task.receive { result in
                    switch result {
                    case .success(let msg):
                        if case .string(let text) = msg, text.contains("registered") {
                            timeout.cancel()
                            finish(true)
                        } else {
                            readNext(remaining - 1)
                        }
                    case .failure:
                        timeout.cancel()
                        finish(nil)
                    }
                }
            }
            readNext(5)
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
        let mac = DeviceDiscovery.shared.tvMAC
        guard !mac.isEmpty else { completion(false); return }
        let macBytes: [UInt8] = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard macBytes.count == 6 else { completion(false); return }
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

// MARK: - NVIDIA Shield Control (ADB)

class ShieldController {
    var host: String { DeviceDiscovery.shared.shieldHost }
    private let adbPath = "/opt/homebrew/bin/adb"

    private func runADB(_ args: [String], completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.adbPath)
            process.arguments = ["-s", "\(self.host):5555"] + args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                completion(process.terminationStatus == 0, output)
            } catch {
                completion(false, nil)
            }
        }
    }

    func ensureConnected(completion: @escaping (Bool) -> Void) {
        runADB(["connect", "\(host):5555"]) { ok, output in
            let connected = output?.contains("connected") == true
            completion(connected)
        }
    }

    func getState(completion: @escaping (Bool?) -> Void) {
        // Reconnect ADB first (session drops after inactivity), then check power state
        ensureConnected { [self] connected in
            guard connected else {
                completion(nil)
                return
            }
            runADB(["shell", "dumpsys", "power"], timeout: 3) { ok, output in
                guard ok, let output = output else {
                    completion(nil)
                    return
                }
                if output.contains("mWakefulness=Awake") {
                    completion(true)
                } else if output.contains("mWakefulness=Asleep") || output.contains("mWakefulness=Dozing") {
                    completion(false)
                } else {
                    completion(nil)
                }
            }
        }
    }

    func wake(completion: @escaping (Bool) -> Void) {
        ensureConnected { [self] _ in
            runADB(["shell", "input", "keyevent", "KEYCODE_WAKEUP"]) { ok, _ in
                completion(ok)
            }
        }
    }

    func sleep(completion: @escaping (Bool) -> Void) {
        runADB(["shell", "input", "keyevent", "KEYCODE_SLEEP"]) { ok, _ in
            completion(ok)
        }
    }

    func launchPlex(completion: @escaping (Bool) -> Void) {
        ensureConnected { [self] _ in
            // Wake first, then launch Plex
            runADB(["shell", "input", "keyevent", "KEYCODE_WAKEUP"]) { [self] _, _ in
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    self.runADB(["shell", "am", "start", "-n",
                                 "com.plexapp.android/com.plexapp.plex.activities.SplashActivity"]) { ok, _ in
                        completion(ok)
                    }
                }
            }
        }
    }

    // Run ADB with a timeout
    private func runADB(_ args: [String], timeout: TimeInterval, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.adbPath)
            process.arguments = ["-s", "\(self.host):5555"] + args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let deadline = DispatchTime.now() + timeout
                DispatchQueue.global().asyncAfter(deadline: deadline) {
                    if process.isRunning { process.terminate() }
                }
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                completion(process.terminationStatus == 0, output)
            } catch {
                completion(false, nil)
            }
        }
    }
}

// MARK: - Xbox Status

class XboxController {
    var host: String { DeviceDiscovery.shared.xboxHost }

    func getState(completion: @escaping (Bool?) -> Void) {
        // Xbox responds to SSDP unicast when awake, silent in standby
        DispatchQueue.global().async {
            let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard sock >= 0 else { completion(nil); return }

            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(1900).bigEndian
            addr.sin_addr.s_addr = inet_addr(self.host)

            let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n"
            let sent = msg.withCString { ptr in
                withUnsafePointer(to: &addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                        sendto(sock, ptr, strlen(ptr), 0, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            guard sent > 0 else { close(sock); completion(nil); return }

            var buf = [UInt8](repeating: 0, count: 2048)
            let n = recv(sock, &buf, buf.count, 0)
            close(sock)

            if n > 0 {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
}

// MARK: - Plex Server

class PlexController {
    var host: String { DeviceDiscovery.shared.plexHost }
    var token: String { DeviceDiscovery.shared.plexToken }

    func getState(completion: @escaping (Bool?, Int?) -> Void) {
        guard !token.isEmpty else { completion(nil, nil); return }
        let url = URL(string: "http://\(host):32400/status/sessions?X-Plex-Token=\(token)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else {
                completion(nil, nil)
                return
            }
            // Server is reachable
            // Count active sessions from size attribute
            if let range = text.range(of: "size=\"") {
                let start = range.upperBound
                if let end = text[start...].firstIndex(of: "\"") {
                    let count = Int(text[start..<end]) ?? 0
                    completion(true, count)
                    return
                }
            }
            completion(true, 0)
        }.resume()
    }

    func scanLibrary(_ key: String, completion: @escaping (Bool) -> Void) {
        guard !token.isEmpty else { completion(false); return }
        let url = URL(string: "http://\(host):32400/library/sections/\(key)/refresh?X-Plex-Token=\(token)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            completion(ok)
        }.resume()
    }
}

// MARK: - iMac Status

class IMacController {
    var host: String { DeviceDiscovery.shared.imacHost }

    func getState(completion: @escaping (Bool?) -> Void) {
        DispatchQueue.global().async {
            let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard sock >= 0 else { completion(nil); return }

            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(22).bigEndian
            addr.sin_addr.s_addr = inet_addr(self.host)

            let result = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                    connect(sock, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            close(sock)
            completion(result == 0 ? true : false)
        }
    }
}

// MARK: - Toggle Row View

class ToggleRowView: NSView {
    let toggle = NSSwitch()
    let label = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    let iconView = NSImageView()
    var onToggle: ((Bool) -> Void)?

    let roomLabel = NSTextField(labelWithString: "")

    init(title: String, icon: String, room: String? = nil, width: CGFloat = 280) {
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
        label.frame = NSRect(x: 44, y: 22, width: 120, height: 16)
        addSubview(label)

        // Room label (right of title)
        if let room = room {
            roomLabel.stringValue = room
            roomLabel.font = .systemFont(ofSize: 11)
            roomLabel.textColor = .tertiaryLabelColor
            roomLabel.alignment = .right
            roomLabel.frame = NSRect(x: 140, y: 23, width: 80, height: 14)
            addSubview(roomLabel)
        }

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

    let roomLabel = NSTextField(labelWithString: "")

    init(title: String, icon: String, isOn: Bool?, room: String? = nil, width: CGFloat = 280) {
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
        label.frame = NSRect(x: 44, y: 22, width: 120, height: 16)
        addSubview(label)

        if let room = room {
            roomLabel.stringValue = room
            roomLabel.font = .systemFont(ofSize: 11)
            roomLabel.textColor = .tertiaryLabelColor
            roomLabel.alignment = .right
            roomLabel.frame = NSRect(x: 140, y: 23, width: 80, height: 14)
            addSubview(roomLabel)
        }

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
    let xbox = XboxController()
    let plex = PlexController()
    let imac = IMacController()
    var cxnPowerState: Bool?
    var tvPowerState: Bool?
    var shieldPowerState: Bool?
    var xboxPowerState: Bool?
    var plexOnline: Bool?
    var imacOnline: Bool?
    var plexSessions: Int = 0
    var roonRunning: Bool = false
    var statusTimer: Timer?
    var cxnToggle: ToggleRowView!
    var tvToggle: ToggleRowView!
    var shieldToggle: ToggleRowView!
    var roonToggle: ToggleRowView!
    var plexToggle: ToggleRowView!
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
        cxnToggle = ToggleRowView(title: "CXN v2", icon: "hifispeaker.fill", room: "Living Room")
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
        tvToggle = ToggleRowView(title: "LG OLED", icon: "tv.fill", room: "Living Room")
        tvToggle.setState(tvPowerState == true)
        tvToggle.setStatus(tvPowerState == true ? "On" : "Off / Standby")
        tvToggle.iconView.contentTintColor = tvPowerState == true ? .controlAccentColor : .secondaryLabelColor
        tvToggle.onToggle = { [weak self] on in
            self?.toggleTV(on)
        }
        let tvItem = NSMenuItem()
        tvItem.view = tvToggle
        menu.addItem(tvItem)

        // Shield Toggle (ADB control)
        shieldToggle = ToggleRowView(title: "NVIDIA Shield", icon: "gamecontroller.fill", room: "Living Room")
        shieldToggle.setState(shieldPowerState == true)
        shieldToggle.setStatus(shieldPowerState == true ? "Awake" : shieldPowerState == false ? "Asleep" : "Unreachable")
        shieldToggle.iconView.contentTintColor = shieldPowerState == true ? .controlAccentColor : .secondaryLabelColor
        shieldToggle.onToggle = { [weak self] on in
            self?.toggleShield(on)
        }
        let shieldItem = NSMenuItem()
        shieldItem.view = shieldToggle
        menu.addItem(shieldItem)

        // Shield Services submenu (filtered by settings)
        let enabledApps = shieldAppRegistry.filter { Settings.shared.isServiceEnabled($0.package) }
        if !enabledApps.isEmpty {
            let servicesItem = NSMenuItem(title: "  Services", action: nil, keyEquivalent: "")
            servicesItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
            let servicesMenu = NSMenu()
            for app in enabledApps {
                let item = NSMenuItem(title: app.name, action: #selector(launchShieldService(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app.package
                item.image = loadAppIcon(app)
                servicesMenu.addItem(item)
            }
            servicesItem.submenu = servicesMenu
            menu.addItem(servicesItem)
        }

        // Xbox Status (display only — CEC linked to TV, independent power)
        let xboxRow = StatusRowView(title: "Xbox", icon: "xbox.logo", isOn: xboxPowerState, room: "Living Room")
        xboxRow.statusLabel.stringValue = xboxPowerState == true ? "On" : "Off"
        let xboxItem = NSMenuItem()
        xboxItem.view = xboxRow
        menu.addItem(xboxItem)

        // iMac Status
        let imacRow = StatusRowView(title: "iMac", icon: "desktopcomputer", isOn: imacOnline, room: "Office")
        imacRow.statusLabel.stringValue = imacOnline == true ? "Online" : imacOnline == false ? "Offline" : "Unknown"
        let imacItem = NSMenuItem()
        imacItem.view = imacRow
        menu.addItem(imacItem)

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

        // Plex Toggle (wakes Shield + launches Plex)
        let plexStatus: String
        if plexOnline == true {
            plexStatus = plexSessions > 0 ? "\(plexSessions) active stream\(plexSessions == 1 ? "" : "s")" : "Server idle"
        } else {
            plexStatus = "Server offline"
        }
        plexToggle = ToggleRowView(title: "Plex", icon: "film.fill")
        // Use Plex PNG icon
        let plexIconPaths = [
            NSString(string: "~/Documents/Projects/home-control/MenuBarApp/icons/plex.png").expandingTildeInPath,
            "icons/plex.png"
        ]
        for path in plexIconPaths {
            if let img = NSImage(contentsOfFile: path) {
                img.size = NSSize(width: 16, height: 16)
                plexToggle.iconView.image = img
                plexToggle.iconView.contentTintColor = nil
                break
            }
        }
        plexToggle.setState(shieldPowerState == true && plexOnline == true)
        plexToggle.setStatus(plexStatus)
        plexToggle.onToggle = { [weak self] on in
            self?.togglePlex(on)
        }
        let plexItem = NSMenuItem()
        plexItem.view = plexToggle
        menu.addItem(plexItem)

        // Plex Scan submenu
        if plexOnline == true {
            let scanItem = NSMenuItem(title: "  Scan Library", action: nil, keyEquivalent: "")
            let scanMenu = NSMenu()
            let scanMovies = NSMenuItem(title: "Movies", action: #selector(scanPlexMovies), keyEquivalent: "")
            scanMovies.target = self
            let scanTV = NSMenuItem(title: "TV Programmes", action: #selector(scanPlexTV), keyEquivalent: "")
            scanTV.target = self
            let scanMusic = NSMenuItem(title: "Music", action: #selector(scanPlexMusic), keyEquivalent: "")
            scanMusic.target = self
            scanMenu.addItem(scanMovies)
            scanMenu.addItem(scanTV)
            scanMenu.addItem(scanMusic)
            scanItem.submenu = scanMenu
            scanItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            menu.addItem(scanItem)
        }

        menu.addItem(NSMenuItem.separator())

        // ── SETTINGS ──
        let settingsMenu = NSMenu()
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = Settings.shared.launchAtLogin ? .on : .off
        settingsMenu.addItem(launchItem)

        // Shield Services visibility
        let servicesSettingsItem = NSMenuItem(title: "Shield Services", action: nil, keyEquivalent: "")
        let servicesSettingsMenu = NSMenu()
        for app in shieldAppRegistry {
            let item = NSMenuItem(title: app.name, action: #selector(toggleServiceVisibility(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.package
            item.state = Settings.shared.isServiceEnabled(app.package) ? .on : .off
            servicesSettingsMenu.addItem(item)
        }
        servicesSettingsItem.submenu = servicesSettingsMenu
        settingsMenu.addItem(servicesSettingsItem)

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

        cxn.getState { [weak self] power, volume, source in
            DispatchQueue.main.async {
                self?.cxnPowerState = power
                self?.buildMenuIfNeeded()
            }
        }

        tv.getState { [weak self] power in
            DispatchQueue.main.async {
                if power == true { self?.tv.knownOff = false }
                self?.tvPowerState = power
                self?.buildMenuIfNeeded()
            }
        }

        shield.getState { [weak self] power in
            DispatchQueue.main.async {
                self?.shieldPowerState = power
                self?.buildMenuIfNeeded()
            }
        }

        xbox.getState { [weak self] power in
            DispatchQueue.main.async {
                self?.xboxPowerState = power
                self?.buildMenuIfNeeded()
            }
        }

        plex.getState { [weak self] online, sessions in
            DispatchQueue.main.async {
                self?.plexOnline = online
                self?.plexSessions = sessions ?? 0
                self?.buildMenuIfNeeded()
            }
        }

        imac.getState { [weak self] online in
            DispatchQueue.main.async {
                self?.imacOnline = online
                self?.buildMenuIfNeeded()
            }
        }
    }

    private var lastMenuBuild: Date = .distantPast
    func buildMenuIfNeeded() {
        // Debounce — only rebuild once per poll cycle
        let now = Date()
        if now.timeIntervalSince(lastMenuBuild) > 0.3 {
            lastMenuBuild = now
            // Delay slightly to let both callbacks arrive
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.buildMenu()
            }
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

    func toggleShield(_ on: Bool) {
        guard !busyLock else { return }
        busyLock = true
        shieldToggle.setStatus(on ? "Waking…" : "Sleeping…")
        shieldToggle.setEnabled(false)

        if on {
            shield.wake { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.busyLock = false
                    self?.pollState()
                }
            }
        } else {
            shield.sleep { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.busyLock = false
                    self?.pollState()
                }
            }
        }
    }

    func togglePlex(_ on: Bool) {
        guard !busyLock else { return }
        busyLock = true
        plexToggle.setStatus(on ? "Launching…" : "Stopping…")
        plexToggle.setEnabled(false)

        if on {
            // Wake Shield and launch Plex
            shield.launchPlex { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.busyLock = false
                    self?.pollState()
                }
            }
        } else {
            // Sleep the Shield (closes Plex)
            shield.sleep { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.busyLock = false
                    self?.pollState()
                }
            }
        }
    }

    @objc func launchShieldService(_ sender: NSMenuItem) {
        guard let package = sender.representedObject as? String else { return }
        shield.ensureConnected { [self] _ in
            shield.wake { [self] _ in
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/adb")
                    process.arguments = ["-s", "\(self.shield.host):5555", "shell",
                                         "monkey", "-p", package, "-c",
                                         "android.intent.category.LEANBACK_LAUNCHER", "1"]
                    try? process.run()
                    process.waitUntilExit()
                }
            }
        }
    }

    @objc func scanPlexMovies() { plex.scanLibrary("1") { _ in } }
    @objc func scanPlexTV() { plex.scanLibrary("3") { _ in } }
    @objc func scanPlexMusic() { plex.scanLibrary("2") { _ in } }

    @objc func toggleServiceVisibility(_ sender: NSMenuItem) {
        guard let package = sender.representedObject as? String else { return }
        let current = Settings.shared.isServiceEnabled(package)
        Settings.shared.setServiceEnabled(package, enabled: !current)
        buildMenu()
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
