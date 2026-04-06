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
- [x] NVIDIA Shield — ADB control (wake, sleep, app launch)
- [x] Xbox — SSDP status polling
- [x] Plex Media Server — session count, library scan triggers
- [ ] LG TV app launcher — SSAP `system.launcher/launch` for webOS apps (Netflix, Disney+, iPlayer, etc.)
- [ ] Sony Bravia (REST API)
- [ ] Samsung Tizen (WebSocket)
- [ ] Apple TV (MRP protocol)
- [ ] Denon/Marantz AVR (HTTP/telnet)
- [ ] Sonos (UPnP/SOAP)

## Phase 4: Web Control Surface
- [ ] Node.js HTTP/WebSocket server on Mac as device hub
- [ ] REST API wrapping all device drivers (CXN, TV, Shield, Xbox, Plex)
- [ ] WebSocket push for real-time state updates
- [ ] Touch-optimised web UI — dark theme, grid layout, large touch targets
- [ ] PWA manifest — add to iPad/iPhone home screen, full-screen, no browser chrome
- [ ] Device cards with toggles, status indicators, now playing
- [ ] Services launcher grid (Shield apps, TV apps)
- [ ] Input switching (HDMI 1–4)
- [ ] CXN now playing, source switching, radio presets
- [ ] Basic auth for web UI (local network security)

## Phase 5: Sessions
- [ ] User-defined sessions (e.g., "Movie Night" = TV on + Shield on + HDMI1 + Plex)
- [ ] "Music" session — CXN power cycle + Roon + TV screen off
- [ ] "Goodnight" — everything off in one click
- [ ] Session templates — Roon, Plex, Gaming, etc.
- [ ] Keyboard shortcuts for sessions (menu bar app)
- [ ] Scheduled sessions (e.g., "turn everything off at midnight")

## Phase 6: Distribution
- [ ] Device discovery/setup flow (replace hand-edited config.local)
- [ ] Config UI instead of config file
- [ ] Documentation for each device pairing step (TV, Shield ADB, Plex token)
- [ ] `npm install && npm start` — zero-config for the server
- [ ] Menu bar app: code signing, notarisation, DMG installer
- [ ] Homebrew cask formula
- [ ] GitHub Releases with universal binary (arm64 + x86_64)

## Phase 7: Community
- [ ] Modular device drivers — add your own hardware
- [ ] Plugin API for third-party device drivers
- [ ] Documentation site
- [ ] Device compatibility database (community-tested)
- [ ] Themeable web UI

## Architecture

Two interfaces, shared device drivers:
- **Menu bar app** (Swift) — quick-access Mac control, runs the device hub
- **Web control surface** (Node + PWA) — full touch UI for iPad/iPhone/any browser

The Mac acts as the hub — it has ADB, SSAP keys, Plex token, SSH. Clients (iPad, phone) connect to its web server. No cloud, no account, local network only.

## Non-Goals
- No cloud/account system — local network only
- No Home app/HomeKit integration (different approach)
