#!/bin/bash
# TRI-PI Bootstrap Installer
# One-liner: curl -sSL https://raw.githubusercontent.com/SamiAhmed7777/tri-pi/main/bootstrap.sh | sudo bash
#
# Downloads the latest release, installs dependencies, creates systemd service,
# and optionally bootstraps the blockchain. ~60 second setup.
#
# For upgrades of an existing install, use upgrade.sh instead.
# For diagnostics, use tri-pi-doctor.sh.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# When piped from curl, $0 is "bash" and $SCRIPT_DIR is the wrong place to
# find lib/common.sh. Use the repo URL instead.
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh"
else
    TMP_LIB=$(mktemp)
    if ! curl -fsSL -o "$TMP_LIB" "https://raw.githubusercontent.com/SamiAhmed7777/tri-pi/main/lib/common.sh"; then
        echo "❌ Failed to download common library" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$TMP_LIB"
    rm -f "$TMP_LIB"
fi

_tpi_init_logging "bootstrap"

echo "╔═══════════════════════════════════════╗"
echo "║   TRI-PI Bootstrap Installer          ║"
echo "╚═══════════════════════════════════════╝"
echo ""

tpi_require_root
tpi_require_arm64

# Get latest release version from GitHub
echo "🔍 Checking latest release..."
VERSION=$(curl -fsL https://api.github.com/repos/SamiAhmed7777/tri-pi/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
if [ -z "$VERSION" ]; then
    tpi_die "Could not detect latest version"
fi
tpi_info "Latest: $VERSION"

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
apt-get update -qq
apt-get install -y -qq tor curl jq > /dev/null 2>&1
tpi_ok "Installed: tor, curl, jq"

# Download release package
echo ""
PACKAGE_URL="https://github.com/SamiAhmed7777/tri-pi/releases/download/$VERSION/tri-pi-${VERSION}-arm64.tar.gz"
SHA_URL="${PACKAGE_URL}.sha256"
echo "⬇️  Downloading TRI-PI $VERSION..."

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

if ! curl -fsL -o tri-pi.tar.gz "$PACKAGE_URL"; then
    tpi_die "Download failed: $PACKAGE_URL"
fi

# Verify SHA256 if available — never install a binary you can't trust
if curl -fsL -o tri-pi.tar.gz.sha256 "$SHA_URL" 2>/dev/null; then
    if sha256sum -c tri-pi.tar.gz.sha256; then
        tpi_ok "SHA256 verified"
    else
        tpi_die "SHA256 mismatch — refusing to install"
    fi
else
    tpi_warn "SHA256 file not available — skipping integrity check"
fi

DL_SIZE=$(du -sh tri-pi.tar.gz | cut -f1)
tpi_ok "Downloaded ($DL_SIZE)"

# Extract and install
echo ""
echo "📦 Installing..."
tar xzf tri-pi.tar.gz

if [ ! -f bin/trianglesd ]; then
    tpi_die "Tarball did not contain bin/trianglesd"
fi

cp bin/trianglesd "$TRI_PI_BIN_PATH"
chmod +x "$TRI_PI_BIN_PATH"
tpi_ok "Binary installed: $(tpi_binary_version)"

# Data directory
mkdir -p "$TRI_PI_DATA_DIR"

# Generate config only if missing — never clobber an existing install
if [ ! -f "${TRI_PI_DATA_DIR}/triangles.conf" ]; then
    tpi_write_default_config "$TRI_PI_DATA_DIR" "$VERSION"
else
    tpi_info "Existing config preserved at ${TRI_PI_DATA_DIR}/triangles.conf"
fi

# Systemd
tpi_write_systemd_unit "$TRI_PI_DATA_DIR"
systemctl enable triangles > /dev/null 2>&1
tpi_ok "Systemd service installed"

# Pre-flight on the tor state dir
tpi_check_tor_state "$TRI_PI_DATA_DIR" || tpi_repair_tor_state "$TRI_PI_DATA_DIR"

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
        tpi_ok "Downloaded"
        echo "📦 Extracting..."
        tar xzf /tmp/triangles-bootstrap.tar.gz -C "${TRI_PI_DATA_DIR}/"
        rm -f /tmp/triangles-bootstrap.tar.gz
        tpi_ok "Blockchain deployed"
    else
        tpi_warn "Bootstrap unreachable — will sync from peers"
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
    tpi_ok "Node is running!"
else
    tpi_warn "Node may still be starting — check: journalctl -u triangles -f"
fi

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║       ✅ Installation Complete!       ║"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "📊 Check status:  trianglesd -datadir=$TRI_PI_DATA_DIR getinfo"
echo "🩺 Run doctor:    sudo $(basename "$0" | sed 's/bootstrap/tri-pi-doctor/')"
echo "🔄 Upgrade later: sudo curl -sSL https://raw.githubusercontent.com/SamiAhmed7777/tri-pi/main/upgrade.sh | bash"
echo ""
echo "📋 View logs:     journalctl -u triangles -f"
echo "                  tail -f $TRI_PI_DATA_DIR/debug.log"
echo "                  tail -f $TRI_PI_RUNTIME_LOG"
echo "                  tail -f $TRI_PI_SYSTEMD_STDERR"
echo "🧅 Onion address: cat $TRI_PI_DATA_DIR/onion/hostname"
echo "🔄 Auto-starts on boot"
echo "🧪 Bootstrap log: $TPI_LOG_FILE"
echo ""
