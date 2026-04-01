#!/bin/bash
# TRI-PI Bootstrap Installer
# Ultra-lightweight initial download with optional blockchain bootstrap

set -e

VERSION="v5.4.4"
BINARY_URL="https://github.com/SamiAhmed7777/tri-pi/raw/main/releases/trianglesd-upx"
BLOCKCHAIN_URL="https://example.com/tri-blockchain-latest.tar.gz"  # TODO: Update with actual URL

echo "╔═══════════════════════════════════════╗"
echo "║   TRI-PI $VERSION Bootstrap Installer  ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# Check ARM64
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]]; then
    echo "❌ Error: This installer requires ARM64 architecture (aarch64)"
    echo "   Detected: $ARCH"
    exit 1
fi

echo "✓ ARM64 architecture detected"

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y tor curl bc > /dev/null 2>&1

echo "✓ Dependencies installed"

# Download binary
echo ""
echo "⬇️  Downloading trianglesd binary (1.6MB, UPX-compressed)..."

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

if ! curl -L -o trianglesd "$BINARY_URL" 2>/dev/null; then
    echo "❌ Download failed. Falling back to full package..."
    PACKAGE_URL="https://github.com/SamiAhmed7777/tri-pi/releases/download/$VERSION/tri-pi-$VERSION-arm64.tar.gz"
    curl -L -o tri-pi.tar.gz "$PACKAGE_URL"
    tar xzf tri-pi.tar.gz
    cd tri-pi-$VERSION-arm64
    sudo cp bin/trianglesd /usr/local/bin/
else
    echo "✓ Binary downloaded"
    chmod +x trianglesd
    sudo cp trianglesd /usr/local/bin/
fi

# Verify installation
echo ""
echo "✅ Binary installed!"
trianglesd --version

# Create config directory
mkdir -p ~/.triangles

# Blockchain bootstrap option
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Blockchain Sync Options"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Choose sync method:"
echo "  [1] Download bootstrap blockchain (FAST - recommended for Pi)"
echo "      ~500MB download, start at current block height"
echo ""
echo "  [2] Sync from scratch (SLOW - may take days on Pi)"
echo "      Start from genesis block"
echo ""
read -p "Your choice [1/2]: " SYNC_CHOICE

if [[ "$SYNC_CHOICE" == "1" ]]; then
    echo ""
    echo "⬇️  Downloading blockchain bootstrap..."
    echo "   This will save hours/days of initial sync!"
    echo ""
    
    if curl -L -o blockchain.tar.gz "$BLOCKCHAIN_URL" 2>/dev/null; then
        echo "✓ Blockchain downloaded"
        echo "📦 Extracting to ~/.triangles/ ..."
        
        tar xzf blockchain.tar.gz -C ~/
        
        BLOCK_HEIGHT=$(grep -oP 'Block Height: \K[0-9]+' ~/snapshot-info.txt 2>/dev/null || echo "latest")
        echo "✓ Blockchain extracted (starting from block $BLOCK_HEIGHT)"
        rm -f blockchain.tar.gz ~/snapshot-info.txt
    else
        echo "⚠️  Bootstrap download failed, will sync from scratch"
    fi
else
    echo "✓ Will sync from genesis block"
fi

# Generate random RPC password
RPC_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)

# Create config if needed
if [[ ! -f ~/.triangles/triangles.conf ]]; then
    echo ""
    echo "📝 Creating configuration..."
    cat > ~/.triangles/triangles.conf << CONFIG
server=1
daemon=1
listen=1
txindex=1

# RPC settings
rpcuser=trianglesrpc
rpcpassword=$RPC_PASS
rpcallowip=127.0.0.1
rpcport=8332

# Network
port=8333
maxconnections=50

# Performance tuning for Raspberry Pi
dbcache=100
maxmempool=50
CONFIG
    echo "✓ Configuration created"
fi

# Enable Tor service
sudo systemctl enable tor > /dev/null 2>&1
sudo systemctl start tor > /dev/null 2>&1
echo "✓ Tor service enabled"

# Cleanup
cd ~
rm -rf "$TMP_DIR"

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║          Installation Complete!       ║"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "🚀 Start your node:"
echo "   trianglesd"
echo ""
echo "📊 Check status:"
echo "   trianglesd getinfo"
echo ""
echo "🔍 View your onion address (after first run):"
echo "   cat ~/.triangles/onion/private_key"
echo ""
echo "💡 Tip: First sync may take a while. Check progress with:"
echo "   watch -n5 'trianglesd getinfo | grep blocks'"
echo ""
echo "Happy mining! 🎯"
