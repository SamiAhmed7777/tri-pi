#!/bin/bash
# TRI-PI Bootstrap Installer
# Ultra-lightweight initial download, then fetches optimized binary

set -e

echo "╔═══════════════════════════════════════╗"
echo "║   TRI-PI v5.4.4 Bootstrap Installer  ║"
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
sudo apt-get install -y tor curl upx-ucl > /dev/null 2>&1

echo "✓ Dependencies installed (tor, curl, upx-ucl)"

# Download UPX-compressed binary (1.6MB instead of 5.1MB!)
echo ""
echo "⬇️  Downloading optimized binary (1.6MB, UPX-compressed)..."

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

# GitHub release URL (we'll create this as a separate release asset)
BINARY_URL="https://github.com/SamiAhmed7777/tri-pi/releases/download/v5.4.4/trianglesd-upx-arm64"

if ! curl -L -o trianglesd "$BINARY_URL" 2>/dev/null; then
    echo "❌ Download failed. Falling back to full package..."
    curl -L -o tri-pi.tar.gz "https://github.com/SamiAhmed7777/tri-pi/releases/download/v5.4.4/tri-pi-v5.4.4-arm64.tar.gz"
    tar xzf tri-pi.tar.gz
    cd tri-pi-v5.4.4-arm64
    sudo cp bin/trianglesd /usr/local/bin/
else
    echo "✓ Binary downloaded (UPX-compressed)"
    chmod +x trianglesd
    sudo cp trianglesd /usr/local/bin/
fi

# Verify
echo ""
echo "✅ Installation complete!"
echo ""
trianglesd --version

# Create config directory
mkdir -p ~/.triangles

# Generate random RPC password
RPC_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)

# Check if config exists
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

# Tor (managed automatically by trianglesd)
# No manual Tor configuration needed!
CONFIG
    echo "✓ Configuration created at ~/.triangles/triangles.conf"
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
echo "║          Installation Ready!          ║"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "Start your node:"
echo "  trianglesd"
echo ""
echo "Check status:"
echo "  trianglesd getinfo"
echo ""
echo "View your onion address (after first run):"
echo "  cat ~/.triangles/onion_private_key"
echo ""
echo "Happy mining! 🚀"
