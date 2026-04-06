# HiFi Control

> **Experimental** — This is a personal project exploring local network control of home AV devices from the macOS menu bar. It works for the specific hardware listed below, but is not yet a general-purpose tool. See [ROADMAP.md](ROADMAP.md) for the plan to make it configurable and distributable.

A native macOS menu bar app for controlling home audio/video devices over the local network.

Built in Swift with zero dependencies — uses WebSocket, HTTP, Wake-on-LAN, and mDNS discovery to communicate directly with devices.

## Supported Devices

| Device | Protocol | On | Off | Status |
|---|---|---|---|---|
| Cambridge Audio CXN v2 | StreamMagic WebSocket (SMOIP) | Power cycle | WebSocket | Live polling |
| LG webOS TV | SSAP WebSocket + WoL | Wake-on-LAN | SSAP turnOff | WebSocket registration |
| NVIDIA Shield | HDMI-CEC (via TV) | — | — | Mirrors TV state |

## Features

- **Toggle switches** for each device with live status indicators
- **Roon session management** — power cycles CXN, launches/quits Roon in one toggle
- **mDNS discovery** — finds CXN via Bonjour, resolves TV by MAC from ARP table
- **Hardcoded fallback IPs** if discovery fails
- **Launch at Login** via macOS native SMAppService
- **No dock icon** — menu bar only (LSUIElement)

## Build

Requires macOS 13+ and Swift 5+.

```bash
cd MenuBarApp
swiftc -o HiFiControl HiFiControl.swift -framework AppKit -framework Foundation -swift-version 5
```

## Install

```bash
# Build the app bundle
cd MenuBarApp
swiftc -o HiFiControl HiFiControl.swift -framework AppKit -framework Foundation -swift-version 5
cp HiFiControl "HiFi Control.app/Contents/MacOS/HiFi Control"

# Copy to Applications (optional)
cp -r "HiFi Control.app" /Applications/
```

## Pairing

### Cambridge Audio CXN v2
No pairing required — the StreamMagic API is open on the local network.

### LG webOS TV
First run requires accepting a pairing prompt on the TV. Use `lgtv2` (Node) to pair:

```bash
npm install lgtv2
node -e "
import lgtv2 from 'lgtv2';
const tv = lgtv2({ url: 'ws://YOUR_TV_IP:3000' });
tv.on('prompt', () => console.log('Accept on TV'));
tv.on('connect', () => { console.log('Paired'); process.exit(0); });
"
```

The client key is saved to `~/Library/Preferences/lgtv2/` and read automatically by the app.

## Project Structure

```
home-control/
├── MenuBarApp/
│   ├── HiFiControl.swift          # Single-file app source
│   └── HiFi Control.app/          # Built app bundle
│       └── Contents/
│           ├── Info.plist
│           ├── MacOS/HiFi Control
│           └── Resources/AppIcon.icns
├── start-roon.mjs                 # Standalone Node script (CXN power cycle + Roon launch)
├── stop-roon.mjs                  # Standalone Node script (Roon quit + CXN off)
├── cxn-test.mjs                   # CXN power off/on test script
├── package.json
└── README.md
```

## Network Requirements

All devices must be on the same local network. The app communicates on:

| Port | Protocol | Device |
|---|---|---|
| 80 | WebSocket | CXN v2 (ws://host/smoip) |
| 3000 | WebSocket | LG TV (SSAP) |
| 9 | UDP broadcast | Wake-on-LAN (TV) |
| 5353 | mDNS | Device discovery |

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the plan to make this a distributable app.

## Licence

MIT
