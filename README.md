# 🤖 XARVIN — AI Desktop Companion for Linux & Wayland

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Quickshell](https://img.shields.io/badge/UI-Quickshell-ff79c6.svg)](https://git.outfoxxed.me/outfoxxed/quickshell)
[![Rust](https://img.shields.io/badge/Daemon-Rust-orange.svg)](https://www.rust-lang.org/)
[![Voice](https://img.shields.io/badge/TTS-Deepgram%20Aura%202-purple.svg)](https://deepgram.com)

**XARVIN** is a high-performance, resident voice AI desktop companion built for Linux Wayland desktops (Hyprland, Omarchy, Sway, Niri, River) and powered by [Quickshell](https://git.outfoxxed.me/outfoxxed/quickshell).

It provides an elegant, keyboard-driven bottom command bar (<kbd>Super</kbd> + <kbd>X</kbd>), animated 3D halftone Thinking Orbs, lightning-fast streaming neural voice synthesis via Deepgram Aura 2, and persistent agent reasoning powered by Antigravity (`agy`), Composio MCP, and Octopus MCP (WhatsApp).

---

## 📑 Table of Contents
1. [Features](#-features)
2. [Architecture](#-architecture)
3. [Prerequisites](#-prerequisites)
4. [One-Click Installation](#-one-click-installation)
5. [Configuration](#-configuration)
6. [Desktop Keybindings](#-desktop-keybindings)
7. [CLI Reference](#-cli-reference)
8. [Project Layout](#-project-layout)
9. [Troubleshooting](#-troubleshooting)

---

## ✨ Features

- **Floating Overlay Command Bar**: Global bottom-anchored input pill (`WlrLayershell`) styled with pitch-black `#000000` background, unvarying `#121212` border, and smooth autofocus.
- **Embedded 3D Halftone Thinking Orb**: 60 FPS mathematical canvas orb reacting dynamically across 5 operational states:
  - `idle`: Rotating 3D Halftone Globe
  - `thinking`: Mathematical Rubik solving geometry
  - `working`: Dynamic orbital particle spinning
  - `speaking`: Organic waveform and audio ripple pulsations
  - `listening`: Responsive audio waves
- **Streaming Neural Voice AI (Deepgram Aura 2)**: Continuous, jitter-buffered real-time MP3 streaming via `mpv` with sub-200ms latency, zero gap between sentences, and zero local CPU load. Also supports ElevenLabs as an alternative engine.
- **Zero-Latency Rust Daemon**: Native async Rust daemon (`xarvin-daemon`) keeping an active warm Antigravity CLI brain session in memory with zero cold-start delay.
- **Tool & Agent Integrations**:
  - **Composio MCP**: System management, calendar, browser, and developer integrations.
  - **Octopus MCP**: Personal WhatsApp messaging, contact queries, and chat management.
  - **System Briefings**: Live resource metrics, security anomaly audits, and headline briefings.
- **Standalone & Portable**: Decoupled from third-party plugins—works natively on any Wayland desktop running Quickshell.

---

## 🏗 Architecture

```mermaid
flowchart TD
    User["User (<kbd>Super + X</kbd>)"] -->|Types Command| Notch["XARVIN Quickshell Overlay (WlrLayershell)"]
    Notch -->|Unix Socket /run/user/1000/xarvin.sock| Daemon["Native Rust Brain Daemon (xarvin-daemon)"]
    Daemon -->|JSON Stream (Warm Cache)| Agy["Antigravity CLI (gemini-3.8-flash-low)"]
    Agy -->|Tool Calls| MCP["Composio MCP / Octopus MCP (WhatsApp)"]
    Agy -->|Streaming Response Sentences| Daemon
    Daemon -->|JSON IPC| TTS["Speech Synthesis Worker (xarvin_tts_worker.py)"]
    TTS -->|Streaming Audio API| Deepgram["Deepgram Aura 2 / ElevenLabs"]
    Deepgram -->|Streaming MP3 (Pipelined)| Audio["mpv (PipeWire Output)"]
    Daemon -->|Atomic State Broadcast| State["xarvin-state.json"]
    State -->|FileView Inotify| Notch
    State -->|FileView Inotify| Bar["Omarchy Status Bar Widget (XarvinBar.qml)"]
```

---

## 📦 Prerequisites

Ensure you have the following installed on your system:

| Tool | Arch / Omarchy | Fedora | Ubuntu / Debian |
|---|---|---|---|
| **Rust & Cargo** | `sudo pacman -S rust` | `sudo dnf install cargo` | `sudo apt install cargo` |
| **Python 3** | `sudo pacman -S python` | `sudo dnf install python3` | `sudo apt install python3 python3-venv` |
| **Quickshell** | `sudo pacman -S quickshell` | [Build from source](https://git.outfoxxed.me/outfoxxed/quickshell) | [Build from source](https://git.outfoxxed.me/outfoxxed/quickshell) |
| **Audio Player** | `sudo pacman -S mpv` | `sudo dnf install mpv` | `sudo apt install mpv` |
| **Antigravity CLI** | `agy` (Installed in `~/.local/bin/agy`) | `agy` (Installed in `~/.local/bin/agy`) | `agy` (Installed in `~/.local/bin/agy`) |

---

## ⚡ One-Click Installation

Clone the repository and run the automated installer:

```bash
git clone https://github.com/your-username/xarvin.git ~/Projects/xarvin
cd ~/Projects/xarvin
./install.sh
```

### What `install.sh` Does Automatically:
1. Validates system dependencies (`cargo`, `python3`, `mpv`, `quickshell`).
2. Configures a Python virtual environment and installs speech dependencies.
3. Builds the optimized native Rust binary (`xarvin-daemon`) and links `xarvin` to `~/.local/bin/`.
4. Symlinks the Quickshell package to `~/.config/quickshell/xarvin`.
5. Configures the Omarchy Status Bar widget plugin (if Omarchy is detected).
6. Creates your `config/xarvin.env` configuration file from the template.
7. Installs, reloads, and enables systemd user services (`xarvin.service` and `xarvin-ui.service`).

---

## ⚙️ Configuration

Edit `config/xarvin.env` with your desired settings and API credentials:

```bash
nano ~/Projects/xarvin/config/xarvin.env
```

```env
# XARVIN Configuration
ASSISTANT_NAME=XARVIN

# Primary High-Performance Cloud TTS (Deepgram Aura 2)
TTS_ENGINE=deepgram
DEEPGRAM_API_KEY=your_deepgram_api_key_here
DEEPGRAM_VOICE=aura-2-orion-en

# Optional ElevenLabs Settings (Alternative engine)
ELEVENLABS_API_KEY=your_elevenlabs_key_here
ELEVENLABS_VOICE_ID=xcy4I5tPh94DVcviSzGr
ELEVENLABS_MODEL=eleven_turbo_v2_5
```

After modifying credentials, restart the services:
```bash
xarvin restart
```

---

## ⌨️ Desktop Keybindings

### Hyprland (`bindings.lua` or `hyprland.conf`)

Add a global key shortcut to toggle the command bar anywhere on your system:

**For Omarchy / Hyprland Lua (`~/.config/hypr/bindings.lua`):**
```lua
o.bind("SUPER + X", "XARVIN Command Bar", "xarvin toggle")
```

**For Standard `hyprland.conf` (`~/.config/hypr/hyprland.conf`):**
```ini
bind = $mainMod, X, exec, xarvin toggle
```

**For Sway (`~/.config/sway/config`):**
```ini
bindsym $mod+x exec xarvin toggle
```

---

## 🛠 CLI Reference

The `xarvin` command provides complete control over the system:

| Command | Action |
|---|---|
| `xarvin toggle` | Toggles the overlay command bar open or closed |
| `xarvin open` | Opens the command bar and grants keyboard focus |
| `xarvin close` | Closes the command bar |
| `xarvin ask "<text>"` | Queries XARVIN directly from terminal or scripts |
| `xarvin stop` | Immediately stops ongoing speech playback or active tool execution |
| `xarvin status` | Shows systemd service health and daemon socket status |
| `xarvin start` | Starts background daemon and Quickshell UI services |
| `xarvin restart` | Restarts all XARVIN services |
| `xarvin daemon` | Runs the daemon in the foreground (useful for development and debugging) |

---

## 📂 Project Layout

```
xarvin/
├── bin/
│   ├── xarvin                      # Global CLI wrapper and shortcut dispatcher
│   └── xarvin-daemon               # Compiled native Rust daemon binary
├── config/
│   ├── xarvin.env                  # Active credentials and voice configuration (git-ignored)
│   └── xarvin.env.example          # Safe configuration template
├── daemon/
│   ├── Cargo.toml                  # Rust dependencies (tokio, serde, reqwest, regex)
│   └── src/main.rs                 # Native daemon server and warm Antigravity session
├── quickshell/
│   ├── shell.qml                   # Standalone Quickshell entrypoint and IPC receiver
│   ├── XarvinNotch.qml             # Floating overlay command bar (WlrLayershell)
│   └── js/
│       └── ThinkingOrbs.js         # 3D Halftone Canvas Orb mathematical algorithms
├── omarchy-plugin/
│   ├── manifest.json               # Omarchy bar widget registration
│   └── XarvinBar.qml               # Bottom panel 3D Voice Orb widget
├── systemd/
│   ├── xarvin.service              # Systemd user service for Rust background brain
│   └── xarvin-ui.service           # Systemd user service for Quickshell UI overlay
├── tts/
│   ├── xarvin_tts_worker.py        # Streaming TTS worker (Deepgram Aura 2 & ElevenLabs)
│   ├── silence_preroll.mp3         # Hardware DAC sleep-prevention preroll
│   └── requirements.txt            # Python dependencies
├── install.sh                      # Fully automated one-click setup script
└── README.md                       # Documentation and architecture guide
```

---

## 🔧 Troubleshooting

### Audio clips first words on Bluetooth / DAC
XARVIN includes a built-in 350ms silence preroll. If your hardware DAC enters sleep mode aggressively, disable sink suspension in PipeWire:
```bash
mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cat << 'EOF' > ~/.config/wireplumber/wireplumber.conf.d/disable-sink-suspend.conf
monitor.bluez.rules = [ { matches = [ { node.name = "~bluez_output.*" } ], actions = { update-props = { session.suspend-timeout-seconds = 0 } } } ]
monitor.alsa.rules = [ { matches = [ { node.name = "~alsa_output.*" } ], actions = { update-props = { session.suspend-timeout-seconds = 0 } } } ]
EOF
systemctl --user restart wireplumber pipewire
```

### Inspect Live Service Logs
```bash
# Check daemon brain logs
journalctl --user -u xarvin.service -f

# Check Quickshell overlay logs
journalctl --user -u xarvin-ui.service -f
```

---

## 📜 License
Distributed under the MIT License.
