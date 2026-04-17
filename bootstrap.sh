#!/bin/bash
# TRI-PI Bootstrap Installer
# One-liner: curl -sSL https://raw.githubusercontent.com/SamiAhmed7777/tri-pi/main/bootstrap.sh | sudo bash
#
# Downloads the latest release, installs dependencies, creates systemd service,
# and optionally bootstraps the blockchain. ~60 second setup.

set -euo pipefail

LOG_DIR="/var/log/tri-pi"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "╔═══════════════════════════════════════╗"
echo "║   TRI-PI Bootstrap Installer          ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# Must be root
if [ "$(id -u)" != "0" ]; then
    echo "❌ Error: Run as root (use sudo)"
    exit 1
fi

# Check ARM64
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]]; then
    echo "❌ Error: This installer requires ARM64 architecture (aarch64)"
    echo "   Detected: $ARCH"
    exit 1
fi

echo "✓ ARM64 detected"

# Get latest release version from GitHub
echo "🔍 Checking latest release..."
VERSION=$(curl -sL https://api.github.com/repos/SamiAhmed7777/tri-pi/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
if [ -z "$VERSION" ]; then
    echo "⚠️  Could not detect latest version"
    exit 1
fi
echo "   Latest: $VERSION"

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
apt-get update -qq
apt-get install -y -qq tor curl > /dev/null 2>&1
echo "✓ Dependencies installed"

# Download release package
echo ""
PACKAGE_URL="https://github.com/SamiAhmed7777/tri-pi/releases/download/$VERSION/tri-pi-${VERSION}-arm64.tar.gz"
echo "⬇️  Downloading TRI-PI $VERSION..."

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

if ! curl -sL -o tri-pi.tar.gz "$PACKAGE_URL"; then
    echo "❌ Download failed: $PACKAGE_URL"
    rm -rf "$TMP_DIR"
    exit 1
fi

DL_SIZE=$(du -sh tri-pi.tar.gz | cut -f1)
echo "✓ Downloaded ($DL_SIZE)"

# Extract and install
echo ""
echo "📦 Installing..."
tar xzf tri-pi.tar.gz

cp bin/trianglesd /usr/local/bin/
chmod +x /usr/local/bin/trianglesd
echo "✓ Binary installed"

# Data directory
DATA_DIR="/root/.triangles"
mkdir -p "$DATA_DIR"

# Generate config
if [ ! -f "$DATA_DIR/triangles.conf" ]; then
    RPC_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    
    cat > "$DATA_DIR/triangles.conf" << CONFIG
# TRI-PI $VERSION Configuration
server=1
listen=1

# RPC
rpcuser=tripi
rpcpassword=$RPC_PASS
rpcallowip=127.0.0.1
rpcport=19199

# Network
port=24112
maxconnections=50

# Performance tuning for ARM/Pi
dbcache=100
maxmempool=50

# Seed nodes
addnode=194.233.88.206
addnode=74.208.167.19
addnode=179.189.35.51
CONFIG
    chmod 600 "$DATA_DIR/triangles.conf"
    echo "✓ Configuration created"
else
    echo "✓ Existing config preserved"
fi

# Systemd service
cat > /usr/local/bin/triangles-start-diagnostics.sh << SERVICEWRAP
#!/bin/bash
set -euo pipefail
DATA_DIR="$DATA_DIR"
LOG_DIR="/var/log/tri-pi"
mkdir -p "$LOG_DIR"
/usr/local/bin/trianglesd -daemon=0 -datadir="$DATA_DIR" >> "$LOG_DIR/runtime.log" 2>&1
SERVICEWRAP
chmod +x /usr/local/bin/triangles-start-diagnostics.sh

cat > /etc/systemd/system/triangles.service << SERVICE
[Unit]
Description=Triangles Cryptocurrency Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/triangles-start-diagnostics.sh
ExecStop=/usr/local/bin/trianglesd -datadir=$DATA_DIR stop
Restart=on-failure
RestartSec=30
TimeoutStopSec=120
LimitNOFILE=65536
StandardOutput=append:/var/log/tri-pi/systemd-stdout.log
StandardError=append:/var/log/tri-pi/systemd-stderr.log

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable triangles > /dev/null 2>&1
echo "✓ Systemd service installed"

# Blockchain bootstrap
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Blockchain Sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  [1] Download bootstrap (~1.3GB) — FAST, recommended"
echo "  [2] Sync from peers — slow (days/weeks on Pi)"
echo ""
read -p "  Choice [1/2]: " SYNC_CHOICE

if [[ "$SYNC_CHOICE" == "1" ]]; then
    BOOTSTRAP_URL="http://74.208.167.19/triangles-bootstrap.tar.gz"
    echo ""
    echo "⬇️  Downloading blockchain bootstrap..."
    
    if curl -L --connect-timeout 30 --max-time 600 -o /tmp/triangles-bootstrap.tar.gz "$BOOTSTRAP_URL" 2>/dev/null; then
        echo "✓ Downloaded"
        echo "📦 Extracting..."
        tar xzf /tmp/triangles-bootstrap.tar.gz -C "$DATA_DIR/"
        rm -f /tmp/triangles-bootstrap.tar.gz
        echo "✓ Blockchain deployed"
    else
        echo "⚠️  Bootstrap unreachable — will sync from peers"
    fi
fi

# Cleanup
cd /
rm -rf "$TMP_DIR"

# Start the node
echo ""
echo "🚀 Starting Triangles node..."
systemctl start triangles
sleep 3

if systemctl is-active --quiet triangles; then
    echo "✓ Node is running!"
else
    echo "⚠️  Node may still be starting — check: journalctl -u triangles -f"
fi

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║       ✅ Installation Complete!       ║"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "📊 Check status:  trianglesd -datadir=$DATA_DIR getinfo"
echo "📋 View logs:     journalctl -u triangles -f"
echo "                  tail -f $DATA_DIR/debug.log"
echo "                  tail -f /var/log/tri-pi/runtime.log"
echo "                  tail -f /var/log/tri-pi/systemd-stderr.log"
echo "🧅 Onion address: cat $DATA_DIR/onion/hostname"
echo "🔄 Auto-starts on boot"
echo "🧪 Bootstrap log: $LOG_FILE"
echo ""
