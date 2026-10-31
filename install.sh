#!/usr/bin/env bash
# ==============================================================================
# XARVIN — One-Click Setup & Installer
# Compatible with Arch Linux, Omarchy, Fedora, Ubuntu/Debian, and Wayland desktops.
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
QUICKSHELL_DIR="${HOME}/.config/quickshell"

echo "=========================================================="
echo "          🤖 XARVIN AI Desktop Companion Setup            "
echo "=========================================================="
echo "Project Path: ${DIR}"
echo ""

# ------------------------------------------------------------------------------
# 1. Dependency Pre-flight Check
# ------------------------------------------------------------------------------
echo "🔍 [1/6] Checking required system dependencies..."

MISSING_DEPS=()
for cmd in cargo rustc python3 quickshell; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_DEPS+=("$cmd")
    fi
done

# Audio backend check (native PipeWire pw-play preferred, mpv/paplay/aplay fallback)
AUDIO_BACKEND=""
for p in pw-play mpv paplay aplay; do
    if command -v "$p" >/dev/null 2>&1; then
        AUDIO_BACKEND="$p"
        break
    fi
done

if [ -z "$AUDIO_BACKEND" ]; then
    MISSING_DEPS+=("pw-play (or mpv)")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "⚠️  Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Please install them via your package manager:"
    echo "  - Arch/Omarchy: sudo pacman -S rust python quickshell pipewire"
    echo "  - Fedora:       sudo dnf install cargo python3 pipewire-utils"
    echo "  - Ubuntu/Debian: sudo apt install cargo python3 python3-venv pipewire-bin"
    echo ""
    read -rp "Do you want to continue anyway? [y/N]: " proceed
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
        echo "Installation aborted."
        exit 1
    fi
else
    echo "✓ All core dependencies found (Audio engine: ${AUDIO_BACKEND})."
fi

# ------------------------------------------------------------------------------
# 2. Python Virtual Environment
# ------------------------------------------------------------------------------
echo "🐍 [2/6] Setting up Python virtual environment for speech worker..."
if [ ! -d "${DIR}/.venv" ]; then
    python3 -m venv "${DIR}/.venv"
fi

if [ -f "${DIR}/tts/requirements.txt" ]; then
    "${DIR}/.venv/bin/pip" install --upgrade pip >/dev/null 2>&1 || true
    "${DIR}/.venv/bin/pip" install -r "${DIR}/tts/requirements.txt" >/dev/null 2>&1 || true
fi
chmod +x "${DIR}/tts/xarvin_tts_worker.py"
echo "✓ Python environment ready."

# ------------------------------------------------------------------------------
# 3. Build & Deploy Native Rust Daemon
# ------------------------------------------------------------------------------
echo "⚡ [3/6] Compiling native Rust daemon (xarvin-daemon)..."
cd "${DIR}/daemon"
cargo build --release
mkdir -p "${DIR}/bin" "${BIN_DIR}"
cp "${DIR}/daemon/target/release/xarvin-daemon" "${DIR}/bin/xarvin-daemon"
cp "${DIR}/daemon/target/release/xarvin-daemon" "${BIN_DIR}/xarvin-daemon"
chmod +x "${DIR}/bin/xarvin" "${DIR}/bin/xarvin-daemon" "${BIN_DIR}/xarvin-daemon"
ln -sf "${DIR}/bin/xarvin" "${BIN_DIR}/xarvin"
echo "✓ Native binary compiled and linked to ${BIN_DIR}/xarvin"

# ------------------------------------------------------------------------------
# 4. Configure Quickshell & Omarchy Bar Plugin
# ------------------------------------------------------------------------------
echo "🎨 [4/6] Linking Quickshell overlay and status bar plugins..."
mkdir -p "${QUICKSHELL_DIR}"
ln -sf "${DIR}/quickshell" "${QUICKSHELL_DIR}/xarvin"

# Optional Omarchy Status Bar Widget
if [ -d "${HOME}/.config/omarchy/plugins" ]; then
    mkdir -p "${HOME}/.config/omarchy/plugins/io.github.xarvin/js"
    cp -r "${DIR}/omarchy-plugin/"* "${HOME}/.config/omarchy/plugins/io.github.xarvin/" 2>/dev/null || true
    echo "✓ Registered 3D Voice Orb plugin in ~/.config/omarchy/plugins/io.github.xarvin"
fi

# ------------------------------------------------------------------------------
# 5. Environment & Credentials Configuration
# ------------------------------------------------------------------------------
echo "⚙️  [5/6] Verifying configuration file..."
if [ ! -f "${DIR}/config/xarvin.env" ]; then
    cp "${DIR}/config/xarvin.env.example" "${DIR}/config/xarvin.env"
    echo "✓ Created new config file at ${DIR}/config/xarvin.env"
    echo "  👉 Edit this file to add your DEEPGRAM_API_KEY or ELEVENLABS_API_KEY."
else
    echo "✓ Configuration file already exists at ${DIR}/config/xarvin.env"
fi

# ------------------------------------------------------------------------------
# 6. Install & Start Systemd Services
# ------------------------------------------------------------------------------
echo "🚀 [6/6] Installing systemd user services..."
mkdir -p "${SYSTEMD_DIR}"

# Write xarvin.service dynamically with exact paths
cat <<EOF > "${SYSTEMD_DIR}/xarvin.service"
[Unit]
Description=XARVIN AI Desktop Companion Background Daemon (Native Rust Brain)
After=graphical-session.target pipewire.service wireplumber.service
Wants=pipewire.service wireplumber.service

[Service]
Type=simple
ExecStart=${DIR}/bin/xarvin-daemon daemon
WorkingDirectory=${DIR}
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

Environment=XARVIN_ENV=${DIR}/config/xarvin.env
Environment=XARVIN_PYTHON=${DIR}/.venv/bin/python3
Environment=XARVIN_TTS_SCRIPT=${DIR}/tts/xarvin_tts_worker.py

[Install]
WantedBy=default.target
EOF

# Write xarvin-ui.service dynamically with exact paths
cat <<EOF > "${SYSTEMD_DIR}/xarvin-ui.service"
[Unit]
Description=XARVIN AI Desktop Companion Quickshell UI Overlay
After=graphical-session.target xarvin.service
Wants=xarvin.service

[Service]
Type=simple
ExecStart=$(command -v quickshell || echo "/usr/bin/quickshell") -c xarvin
WorkingDirectory=${DIR}
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

# Reload and enable services
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable --now xarvin.service xarvin-ui.service 2>/dev/null || true
    echo "✓ Services enabled and started via systemd."
fi

echo ""
echo "=========================================================="
echo "          🎉 XARVIN Setup Completed Successfully!          "
echo "=========================================================="
echo ""
echo "Quick Commands:"
echo "  xarvin toggle       - Open or close the floating command bar"
echo "  xarvin ask <text>   - Query XARVIN directly from the terminal"
echo "  xarvin stop         - Interrupt current speech or tool action"
echo "  xarvin status       - Check daemon and UI health"
echo "  xarvin restart      - Restart background services"
echo ""
echo "Keybinding Setup:"
echo "  Add to ~/.config/hypr/bindings.lua or hyprland.conf:"
echo "    o.bind(\"SUPER + X\", \"XARVIN Command Bar\", \"xarvin toggle\")"
echo "  or:"
echo "    bind = \$mainMod, X, exec, xarvin toggle"
echo ""
