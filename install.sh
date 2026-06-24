#!/bin/bash
# TRI-PI ARM64 Installation Script
# For Raspberry Pi 4/5 (64-bit) and ARM64 servers
#
# For upgrades of an existing install, use upgrade.sh instead.
# For diagnostics, use tri-pi-doctor.sh.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

_tpi_init_logging "install"

echo "====================================="
echo "  TRI-PI ARM64 Installer"
echo "  (Target: $TRI_PI_DATA_DIR)"
echo "====================================="

tpi_require_root
tpi_require_arm64
tpi_check_disk_space "$TRI_PI_DATA_DIR"

# Install dependencies
echo ""
echo "─── Dependencies ────────────────────────────────────"
apt-get update -qq
apt-get install -y -qq tor curl jq > /dev/null 2>&1
tpi_ok "Installed: tor, curl, jq"

# Install binary
echo ""
echo "─── Binary ─────────────────────────────────────────"
if [ ! -f "$SCRIPT_DIR/bin/trianglesd" ]; then
    tpi_die "Missing bin/trianglesd in $SCRIPT_DIR. Wrong package?"
fi
cp "$SCRIPT_DIR/bin/trianglesd" "$TRI_PI_BIN_PATH"
chmod +x "$TRI_PI_BIN_PATH"
tpi_ok "Binary installed to $TRI_PI_BIN_PATH ($(tpi_binary_version))"

# Data directory + config
echo ""
echo "─── Configuration ──────────────────────────────────"
mkdir -p "$TRI_PI_DATA_DIR"
if [ ! -f "${TRI_PI_DATA_DIR}/triangles.conf" ]; then
    tpi_write_default_config "$TRI_PI_DATA_DIR" "$(tpi_binary_version)"
else
    tpi_info "Existing config at ${TRI_PI_DATA_DIR}/triangles.conf — preserved"
fi

# Systemd
echo ""
echo "─── Systemd ────────────────────────────────────────"
tpi_write_systemd_unit "$TRI_PI_DATA_DIR"
systemctl enable triangles > /dev/null 2>&1
tpi_ok "Service enabled (auto-start on boot)"

# Blockchain bootstrap (interactive)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Blockchain Sync Options"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -f "${TRI_PI_DATA_DIR}/blk0001.dat" ]; then
    EXISTING_SIZE=$(du -sh "${TRI_PI_DATA_DIR}/blk0001.dat" | cut -f1)
    tpi_info "Existing blockchain data found ($EXISTING_SIZE)"
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
    BOOTSTRAP_URL="http://74.208.167.19/triangles-bootstrap.tar.gz"
    echo ""
    echo "⬇️  Downloading blockchain bootstrap (~1.3GB)..."
    echo "   This will save days of initial sync time."
    echo ""

    if curl -L --connect-timeout 30 --max-time 600 -o /tmp/triangles-bootstrap.tar.gz "$BOOTSTRAP_URL" 2>/dev/null; then
        DL_SIZE=$(du -sh /tmp/triangles-bootstrap.tar.gz | cut -f1)
        tpi_ok "Downloaded ($DL_SIZE)"
        echo "📦 Extracting to $TRI_PI_DATA_DIR/ ..."

        # Remove old blockchain data before extracting
        rm -rf "${TRI_PI_DATA_DIR}/blk0001.dat" "${TRI_PI_DATA_DIR}/txleveldb" "${TRI_PI_DATA_DIR}/database"
        tar xzf /tmp/triangles-bootstrap.tar.gz -C "${TRI_PI_DATA_DIR}/"
        rm -f /tmp/triangles-bootstrap.tar.gz

        tpi_ok "Blockchain bootstrap deployed"
    else
        tpi_warn "Bootstrap download failed (server unreachable)"
        tpi_warn "  No worries — your node will sync from peers instead."
        tpi_warn "  Tip: you can manually scp a bootstrap later."
    fi
fi

# Pre-flight on the tor state dir (lessons from 2026-06-23 incident)
tpi_check_tor_state "$TRI_PI_DATA_DIR" || {
    tpi_warn "  Tor state directory is non-empty — recommend cleaning before first start"
    tpi_repair_tor_state "$TRI_PI_DATA_DIR"
}

echo ""
echo "====================================="
echo "  ✅ TRI-PI $(tpi_binary_version) Installed!"
echo "====================================="
echo ""
echo "🚀 Start your node:"
echo "   sudo systemctl start triangles"
echo ""
echo "📊 Check status:"
echo "   trianglesd -datadir=$TRI_PI_DATA_DIR getinfo"
echo "   sudo $(basename "$0" | sed 's/install/doctor/')   # diagnostic report"
echo ""
echo "📋 View logs:"
echo "   journalctl -u triangles -f"
echo "   tail -f $TRI_PI_DATA_DIR/debug.log"
echo "   tail -f $TRI_PI_RUNTIME_LOG"
echo "   tail -f $TRI_PI_SYSTEMD_STDERR"
echo ""
echo "🧅 Tor onion address (generated on first run):"
echo "   cat $TRI_PI_DATA_DIR/onion/hostname"
echo ""
echo "🔄 Auto-starts on boot. To upgrade later: sudo ./upgrade.sh"
echo "🧪 Installer log: $TPI_LOG_FILE"
echo ""
