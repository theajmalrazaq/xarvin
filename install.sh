#!/usr/bin/env bash
# XARVIN — Fast Installer & Setup Script
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "=== Installing XARVIN ==="
echo "Project root: $DIR"

# 1. Setup virtual environment for TTS
if [ ! -d "$DIR/.venv" ]; then
    echo "Creating Python virtualenv..."
    python3 -m venv "$DIR/.venv"
fi

echo "Installing TTS requirements..."
"$DIR/.venv/bin/pip" install -r "$DIR/tts/requirements.txt" || true

# 2. Build Rust Daemon
echo "Building native xarvin-daemon..."
cd "$DIR/daemon"
cargo build --release
mkdir -p "$DIR/bin" "$HOME/.local/bin"
cp "$DIR/daemon/target/release/xarvin-daemon" "$DIR/bin/xarvin-daemon"
cp "$DIR/daemon/target/release/xarvin-daemon" "$HOME/.local/bin/xarvin-daemon"
ln -sf "$DIR/bin/xarvin" "$HOME/.local/bin/xarvin"

# 3. Link Quickshell configuration
echo "Configuring Quickshell..."
mkdir -p "$HOME/.config/quickshell"
ln -sf "$DIR/quickshell" "$HOME/.config/quickshell/xarvin"

# 4. Copy default environment config if not present
if [ ! -f "$DIR/config/xarvin.env" ]; then
    cp "$DIR/config/xarvin.env.example" "$DIR/config/xarvin.env"
    echo "Created default config/xarvin.env. Please configure your API keys there."
fi

# 5. Setup systemd user services
echo "Installing systemd services..."
mkdir -p "$HOME/.config/systemd/user"
cp "$DIR/systemd/xarvin.service" "$HOME/.config/systemd/user/xarvin.service"
cp "$DIR/systemd/xarvin-ui.service" "$HOME/.config/systemd/user/xarvin-ui.service"

systemctl --user daemon-reload
systemctl --user enable --now xarvin.service xarvin-ui.service

echo ""
echo "=== XARVIN Installed Successfully! ==="
echo "Commands:"
echo "  xarvin toggle       - Open / close the floating overlay bar"
echo "  xarvin ask <text>   - Query XARVIN from terminal"
echo "  xarvin status       - Check service health"
echo "  xarvin restart      - Restart daemon and UI"
