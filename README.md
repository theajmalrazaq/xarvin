# XARVIN — AI Desktop Companion for Wayland & Quickshell

**XARVIN** is a high-performance, resident AI companion designed natively for Linux desktop environments running Wayland (Hyprland, Sway, Niri, River) and [Quickshell](https://git.outfoxxed.me/outfoxxed/quickshell).

---

## ✨ Features

- **Floating Overlay Command Bar**: A global bottom-floating input bar (`WlrLayershell`) rendered with pure pitch-black background (`#000000`), subtle unvarying `#121212` border, and responsive input controls.
- **Embedded 3D Thinking Orb**: Smooth 60 FPS mathematical canvas orb that dynamically reacts to the assistant's state:
  - **Idle**: Rotating 3D Halftone Globe
  - **Thinking / Processing**: Animated Rubik cube solver
  - **Running Actions**: Spinning dots / orbital geometry
  - **Speaking**: Organic audio ripple and waveform pulsations
- **Authentic British AI Voice**: Powered by Piper neural TTS using the high-fidelity Paul Bettany British assistant model (`jarvis-high.onnx`) with zero cloud cost, 350ms DAC preroll, and instant audio playback. Also supports ElevenLabs streaming as an alternative engine.
- **Ultra-Fast Rust Daemon**: Resident async background daemon (`xarvin-daemon`) keeping an active warm Antigravity CLI brain session ready with zero cold-start penalty.
- **Tool & MCP Routing**: Integrates with Composio MCP for system tasks and Octopus MCP for personal WhatsApp messaging and contact interactions.
- **Standalone Quickshell Package**: Completely decoupled from third-party plugins—runs natively as a Quickshell configuration (`quickshell -c xarvin`).

---

## 📁 Project Structure

```
xarvin/
├── bin/
│   ├── xarvin                  # CLI manager (toggle, ask, stop, restart, etc.)
│   └── xarvin-daemon           # Compiled Rust background daemon binary
├── config/
│   ├── xarvin.env              # Active environment variables and API keys
│   └── xarvin.env.example      # Configuration template
├── daemon/
│   ├── Cargo.toml
│   └── src/main.rs             # Native async Rust brain and Unix socket server
├── quickshell/
│   ├── shell.qml               # Quickshell entrypoint and IPC interface
│   ├── XarvinNotch.qml         # Overlay Command Bar window
│   └── js/
│       └── ThinkingOrbs.js     # 3D Halftone Dot-Orb Canvas algorithms
├── systemd/
│   ├── xarvin.service          # User service for background daemon
│   └── xarvin-ui.service       # User service for Quickshell UI overlay
├── tts/
│   ├── xarvin_tts_worker.py    # Resident Piper / ElevenLabs TTS worker
│   ├── silence_preroll.mp3     # Bluetooth / DAC wake-up preroll
│   └── voices/                 # Neural ONNX voice models
└── install.sh                  # One-click build and setup script
```

---

## 🚀 Quick Start

### 1. Clone & Install
```bash
git clone https://github.com/your-username/xarvin.git ~/Projects/xarvin
cd ~/Projects/xarvin
./install.sh
```

### 2. Configure Keys
Edit `config/xarvin.env` with your API credentials:
```bash
nano ~/Projects/xarvin/config/xarvin.env
```

### 3. Keybinding Setup (Hyprland)
Add this to your `~/.config/hypr/bindings.lua` or `hyprland.conf`:
```lua
-- Hyprland Lua Bindings:
o.bind("SUPER + X", "XARVIN Command Bar", "xarvin toggle")
```
Or in standard `hyprland.conf`:
```conf
bind = $mainMod, X, exec, xarvin toggle
```

---

## ⌨️ CLI Commands

| Command | Action |
|---|---|
| `xarvin toggle` | Toggle the floating overlay command bar |
| `xarvin ask "<prompt>"` | Query XARVIN directly from your terminal or scripts |
| `xarvin stop` | Interrupt ongoing speech or active tool executions |
| `xarvin status` | Inspect socket and service status |
| `xarvin restart` | Restart daemon and UI overlay |
| `xarvin daemon` | Run the daemon in foreground for debugging |

---

## 📜 License
MIT License.
