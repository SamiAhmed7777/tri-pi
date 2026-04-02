#!/bin/bash
# TRI-PI ARM64 Installation Script
# For Raspberry Pi 4/5 (64-bit) and ARM64 servers

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")

echo "====================================="
echo "  TRI-PI $VERSION ARM64 Installer"
echo "====================================="

if [ "$(id -u)" != "0" ]; then
   echo "Error: This script must be run as root (use sudo)"
   exit 1
fi

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "Error: This package is for ARM64 (aarch64) only."
    echo "Detected architecture: $ARCH"
    exit 1
fi

echo "✓ ARM64 architecture detected"

# Install dependencies
echo "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq tor curl > /dev/null 2>&1

echo "✓ Dependencies installed"

# Install binary
echo "Installing trianglesd..."
cp "$SCRIPT_DIR/bin/trianglesd" /usr/local/bin/
chmod +x /usr/local/bin/trianglesd

echo "✓ Binary installed to /usr/local/bin/trianglesd"

# Determine data directory
DATA_DIR="/root/.triangles"
mkdir -p "$DATA_DIR"

# Create config
if [ ! -f "$DATA_DIR/triangles.conf" ]; then
    echo "Creating default configuration..."
    
    RPC_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    
    cat > "$DATA_DIR/triangles.conf" << CONFIG
# TRI-PI $VERSION Configuration
server=1
listen=1

# RPC settings
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
    echo "✓ Configuration created at $DATA_DIR/triangles.conf"
else
    echo "✓ Existing configuration found"
fi

# Install systemd service
echo "Installing systemd service..."
cat > /etc/systemd/system/triangles.service << SERVICE
[Unit]
Description=Triangles Cryptocurrency Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/trianglesd -daemon=0 -datadir=$DATA_DIR
ExecStop=/usr/local/bin/trianglesd -datadir=$DATA_DIR stop
Restart=on-failure
RestartSec=30
TimeoutStopSec=120
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable triangles > /dev/null 2>&1
echo "✓ Systemd service installed and enabled"

# Offer blockchain bootstrap
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Blockchain Sync Options"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -f "$DATA_DIR/blk0001.dat" ]; then
    EXISTING_SIZE=$(du -sh "$DATA_DIR/blk0001.dat" | cut -f1)
    echo "  Existing blockchain data found ($EXISTING_SIZE)"
    echo ""
    read -p "  Skip bootstrap and keep existing data? [Y/n]: " KEEP_EXISTING
    if [[ "$KEEP_EXISTING" =~ ^[Nn] ]]; then
        DO_BOOTSTRAP=1
    else
        DO_BOOTSTRAP=0
    fi
else
    echo "  [1] Download bootstrap blockchain (FAST — recommended)"
    echo "      ~1.3GB download, starts near current block height"
    echo ""
    echo "  [2] Sync from scratch (SLOW — days/weeks on Pi)"
    echo "      Start from genesis block"
    echo ""
    read -p "  Your choice [1/2]: " SYNC_CHOICE
    [[ "$SYNC_CHOICE" == "1" ]] && DO_BOOTSTRAP=1 || DO_BOOTSTRAP=0
fi

if [ "$DO_BOOTSTRAP" -eq 1 ]; then
    BOOTSTRAP_URL="http://194.233.88.206:8085/triangles-bootstrap.tar.gz"
    echo ""
    echo "⬇️  Downloading blockchain bootstrap (~1.3GB)..."
    echo "   This will save days of initial sync time."
    echo ""
    
    if curl -L --connect-timeout 30 --max-time 600 -o /tmp/triangles-bootstrap.tar.gz "$BOOTSTRAP_URL" 2>/dev/null; then
        DL_SIZE=$(du -sh /tmp/triangles-bootstrap.tar.gz | cut -f1)
        echo "✓ Downloaded ($DL_SIZE)"
        echo "📦 Extracting to $DATA_DIR/ ..."
        
        # Remove old blockchain data before extracting
        rm -rf "$DATA_DIR/blk0001.dat" "$DATA_DIR/txleveldb" "$DATA_DIR/database"
        tar xzf /tmp/triangles-bootstrap.tar.gz -C "$DATA_DIR/"
        rm -f /tmp/triangles-bootstrap.tar.gz
        
        echo "✓ Blockchain bootstrap deployed"
    else
        echo "⚠️  Bootstrap download failed (server unreachable)"
        echo "   No worries — your node will sync from peers instead."
        echo "   Tip: you can manually scp a bootstrap later."
    fi
fi

echo ""
echo "====================================="
echo "  ✅ TRI-PI $VERSION Installed!"
echo "====================================="
echo ""
echo "🚀 Start your node:"
echo "   sudo systemctl start triangles"
echo ""
echo "📊 Check status:"
echo "   trianglesd -datadir=$DATA_DIR getinfo"
echo ""
echo "📋 View logs:"
echo "   journalctl -u triangles -f"
echo "   tail -f $DATA_DIR/debug.log"
echo ""
echo "🧅 Tor onion address (generated on first run):"
echo "   cat $DATA_DIR/onion/hostname"
echo ""
echo "🔄 The node will auto-start on boot."
echo ""
