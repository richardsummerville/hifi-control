# HiFi Control — Roadmap

## Phase 1: Xcode Project & Config Layer
- [ ] Migrate from single-file `swiftc` build to Xcode project
- [ ] Extract device configs into a JSON/plist settings file (`~/.config/hifi-control/devices.json`)
- [ ] Create device protocol/interface: `DeviceController` with `powerOn()`, `powerOff()`, `getState()`, `discover()`
- [ ] Refactor CXN, LG TV, and Shield into conforming device drivers
- [ ] App icon (proper .icns asset catalogue)

## Phase 2: Setup UI
- [ ] First-launch setup flow: scan network, present discovered devices
- [ ] "Add Device" panel — pick type (Cambridge Audio, LG TV, Shield), confirm IP/name
- [ ] "Remove Device" option per row
- [ ] Settings window (not just submenu) — device list, polling interval, launch at login
- [ ] Persist config between launches

## Phase 3: Device Support
- [ ] Cambridge Audio — full StreamMagic range (CXN, EVO, MXN, AXN)
- [ ] LG webOS — tested across model years (C/G/A series)
- [ ] NVIDIA Shield — ADB control if network debugging enabled
- [ ] Sony Bravia (REST API)
- [ ] Samsung Tizen (WebSocket)
- [ ] Apple TV (MRP protocol)
- [ ] Denon/Marantz AVR (HTTP/telnet)
- [ ] Sonos (UPnP/SOAP)

## Phase 4: Sessions
- [ ] User-defined sessions (e.g., "Movie Night" = TV on + Shield on + AVR to HDMI2)
- [ ] Session templates — Roon, Plex, Gaming, etc.
- [ ] Keyboard shortcuts for sessions
- [ ] Scheduled sessions (e.g., "turn everything off at midnight")

## Phase 5: Distribution
- [ ] Code signing with Apple Developer certificate
- [ ] Notarisation for Gatekeeper
- [ ] DMG with drag-to-Applications installer
- [ ] Homebrew cask formula
- [ ] GitHub Releases with universal binary (arm64 + x86_64)
- [ ] Sparkle for auto-updates

## Phase 6: Community
- [ ] Plugin API for third-party device drivers
- [ ] Documentation site
- [ ] Device compatibility database (community-tested)

## Non-Goals
- No iOS/iPadOS app (Shortcuts + SSH covers this)
- No cloud/account system — local network only
- No Home app/HomeKit integration (different approach)
