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
if [ ! -f "$SCRIPT_DIR/bin/tri7d" ]; then
    tpi_die "Missing bin/tri7d in $SCRIPT_DIR. Wrong package?"
fi
cp "$SCRIPT_DIR/bin/tri7d" "$TRI_PI_BIN_PATH"
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
    echo "  TRI7-era sync options:"
    echo "  [1] Fresh sync via P2P gap-fill (recommended — default)"
    echo "      tri7d backfills headers/blocks from seed peers; no download needed."
    echo ""
    echo "  [2] Fetch a tri7 blk0001.dat archive (if you host one)"
    echo "      Set TRI_PI_BOOTSTRAP_URL (and optionally TRI_PI_BOOTSTRAP_SHA256)"
    echo "      to the archive URL before running this installer."
    echo "      The canonical archive lives on DNS2: /root/.triangles/blk0001.dat"
    echo ""
    read -p "  Your choice [1/2]: " SYNC_CHOICE
    [[ "$SYNC_CHOICE" == "2" ]] && DO_BOOTSTRAP=1 || DO_BOOTSTRAP=0
fi

if [ "$DO_BOOTSTRAP" -eq 1 ]; then
    # TRI7 era: the legacy bootstrap tarballs (leveldb chainstate from the C++
    # client) are dead URLs AND incompatible with tri7d. tri7d consumes a raw
    # blk0001.dat block archive.
    BOOTSTRAP_URL="${TRI_PI_BOOTSTRAP_URL:-}"
    if [ -z "$BOOTSTRAP_URL" ]; then
        tpi_warn "TRI_PI_BOOTSTRAP_URL is not set — nothing to fetch."
        tpi_warn "  The node will fresh-sync via P2P gap-fill instead (recommended)."
    else
        echo ""
        echo "⬇️  Downloading tri7 blk0001.dat archive..."
        echo "   URL: $BOOTSTRAP_URL"
        echo ""

        if curl -L --connect-timeout 30 --max-time 3600 -o "${TRI_PI_DATA_DIR}/blk0001.dat.part" "$BOOTSTRAP_URL" 2>/dev/null; then
            DL_SIZE=$(du -sh "${TRI_PI_DATA_DIR}/blk0001.dat.part" | cut -f1)
            tpi_ok "Downloaded ($DL_SIZE)"
            if [ -n "${TRI_PI_BOOTSTRAP_SHA256:-}" ]; then
                echo "${TRI_PI_BOOTSTRAP_SHA256}  ${TRI_PI_DATA_DIR}/blk0001.dat.part" | sha256sum -c -
                tpi_ok "SHA256 verified"
            fi
            mv "${TRI_PI_DATA_DIR}/blk0001.dat.part" "${TRI_PI_DATA_DIR}/blk0001.dat"
            tpi_ok "tri7 block archive installed"
        else
            tpi_warn "Archive download failed — the node will fresh-sync via P2P gap-fill."
        fi
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
echo "   tri7d --status --state-dir $TRI_PI_DATA_DIR   # (jq) height + peers"
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
