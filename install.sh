#!/bin/bash
# TRI-PI v5.4.4 ARM64 Installation Script
# For Raspberry Pi 4/5 (64-bit) and ARM64 servers

set -e

echo "====================================="
echo "TRI-PI v5.4.4 ARM64 Installer"
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
apt-get update
apt-get install -y tor curl

echo "✓ Dependencies installed"

# Install binary
echo "Installing trianglesd..."
cp bin/trianglesd /usr/local/bin/
chmod +x /usr/local/bin/trianglesd

echo "✓ Binary installed to /usr/local/bin/trianglesd"

# Create data directory
mkdir -p ~/.triangles

# Create config
if [ ! -f ~/.triangles/triangles.conf ]; then
    echo "Creating default configuration..."
    
    RPC_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    
    cat > ~/.triangles/triangles.conf << CONFIG
# TRI-PI v5.4.4 Configuration
server=1
daemon=1
listen=1
txindex=1

# Tor integration (trianglesd manages tor automatically)
# Do NOT set onion= or tor= - let trianglesd handle it

# Seed nodes (updated v5.4.4)
addnode=gxvrhv3qitnc6kobrhsrse46bmcfitnybapor3or3oczzuxn6hfzxyid.onion
addnode=i6tk7soznftvoibtskwlezviskiererhjndpsmrff4kaxw7jnd5izfqd.onion
addnode=uddaxjbo3lh2zskg7w6gwln4ty5cel7q4c5jbx7fdtv6zf2j47gdlyad.onion
addnode=el5sirhhleecuctpeeprelzubpqmoqivvra3rzlwbjttinxa4fq3wnid.onion
addnode=sj5dhybnlp3v4y5niyc5unrnd6s43lyx5ibup7rolyosjbi2u2hsbvyd.onion
addnode=i3kr5meha7se4ns3wss3h7v46m6uksfzv4wrohdqxpj6n35wyo2bvlid.onion
addnode=futmtrvh6j34t7s6yjdxfia6iwuyfzwh4k5eqfof5kfhoqk3xmi3qoqd.onion

# RPC settings
rpcuser=tripi
rpcpassword=$RPC_PASS
rpcallowip=127.0.0.1
rpcport=24113

# Performance
maxconnections=125
CONFIG

    chmod 600 ~/.triangles/triangles.conf
    echo "✓ Configuration created at ~/.triangles/triangles.conf"
else
    echo "✓ Existing configuration found"
fi

# Enable Tor
echo "Enabling Tor service..."
systemctl enable tor
systemctl start tor

echo ""
echo "====================================="
echo "✅ TRI-PI v5.4.4 Installation Complete!"
echo "====================================="
echo ""
echo "Quick Start:"
echo "  trianglesd                  # Start daemon"
echo "  trianglesd getinfo          # Check status"
echo "  trianglesd help             # List commands"
echo ""
echo "Data directory: ~/.triangles"
echo "Config file: ~/.triangles/triangles.conf"
echo ""
echo "Tor will generate onion address on first run."
echo "Check onion address with: trianglesd getinfo"
echo ""
