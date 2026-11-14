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
apt-get install -y -qq tor curl jq nftables > /dev/null 2>&1
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

# Wallet appliance binaries are REQUIRED — a release without them is not a
# wallet appliance (judge 2026-11-14: silent skips are forbidden).
if [ -f "$SCRIPT_DIR/bin/tri7" ]; then
    cp "$SCRIPT_DIR/bin/tri7" /usr/local/bin/tri7 && chmod +x /usr/local/bin/tri7
    tpi_ok "Wallet CLI installed to /usr/local/bin/tri7"
else
    tpi_die "Missing bin/tri7 (wallet CLI) — this package is not a complete wallet appliance"
fi
if [ -f "$SCRIPT_DIR/bin/store_gapfix" ]; then
    cp "$SCRIPT_DIR/bin/store_gapfix" /usr/local/bin/store_gapfix && chmod +x /usr/local/bin/store_gapfix
    tpi_ok "Store repair tool installed to /usr/local/bin/store_gapfix"
else
    tpi_die "Missing bin/store_gapfix — this package is not a complete wallet appliance"
fi
if [ -f "$SCRIPT_DIR/tri7-appliance" ]; then
    cp "$SCRIPT_DIR/tri7-appliance" /usr/local/bin/tri7-appliance && chmod +x /usr/local/bin/tri7-appliance
    tpi_ok "Appliance manager installed to /usr/local/bin/tri7-appliance"
else
    tpi_die "Missing tri7-appliance manager — this package is not a complete wallet appliance"
fi

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

# No-public-clearnet firewall policy (operator policy: Triangles is NEVER on
# public clearnet — the P2P listener is loopback-backed; tor fronts it)
echo ""
echo "─── Firewall policy ────────────────────────────────"
cat > /etc/tri7-p2p-policy.nft <<NFT
table inet tri7_p2p_policy {
  chain restrict_p2p {
    type filter hook input priority -10; policy accept;
    iifname != "lo" iifname != "tailscale0" tcp dport ${TRI_PI_P2P_PORT} counter drop comment "tri7: no public clearnet"
  }
}
NFT
nft -f /etc/tri7-p2p-policy.nft || tpi_die "Firewall policy FAILED to load — refusing to ship an unprotected wallet. Fix nftables and re-run."
nft list table inet tri7_p2p_policy > /dev/null 2>&1 || tpi_die "tri7_p2p_policy table missing after apply — aborting."
cat > /etc/systemd/system/tri7-p2p-policy.service <<UNITF
[Unit]
Description=tri7 P2P no-public-clearnet policy
After=network-pre.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/tri7-p2p-policy.nft
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNITF
systemctl daemon-reload
systemctl enable tri7-p2p-policy > /dev/null 2>&1 || tpi_die "Could not enable tri7-p2p-policy.service — the firewall policy would not survive reboot; aborting."
systemctl is-enabled tri7-p2p-policy > /dev/null 2>&1 || tpi_die "tri7-p2p-policy.service is not enabled after enable — aborting."
tpi_ok "No-public-clearnet policy active AND persistent across reboot"

# Wallet (2026-11-14: fully functioning wallet, plug in and forget)
echo ""
echo "─── Wallet ─────────────────────────────────────────"
if [ -f "$TRI_PI_WALLET_PATH" ]; then
    tpi_info "Existing wallet kept: $TRI_PI_WALLET_PATH"
else
    if [ -x /usr/local/bin/tri7 ]; then
        echo "  Creating a NEW wallet — 24 words appear below."
        echo "  WRITE THEM ON PAPER. SHOWN ONCE. NO RECOVERY EXISTS."
        echo ""
        /usr/local/bin/tri7 wallet create-seed --out "$TRI_PI_WALLET_PATH"
        chmod 600 "$TRI_PI_WALLET_PATH"
        [ -t 0 ] && { echo ""; read -r -p "  Written down? Press ENTER to continue." _; }
        tpi_ok "Wallet created at $TRI_PI_WALLET_PATH"
    else
        tpi_warn "Wallet CLI missing — wallet creation skipped"
    fi
fi

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
echo "💰 Your wallet:      $TRI_PI_WALLET_PATH"
[ -x /usr/local/bin/tri7 ] && echo "   (24 words you wrote down = the only backup — keep the paper safe)"
echo "🚀 Start your node:"
echo "   sudo systemctl start triangles"
echo ""
echo "📊 Check status:"
echo "   tri7d --status --state-dir $TRI_PI_DATA_DIR   # (jq) height + peers"
echo "   tri7 wallet info --wallet $TRI_PI_WALLET_PATH # keys + addresses"
echo "   curl -sS -X POST http://127.0.0.1:${TRI_PI_RPC_PORT} -d '{\"method\":\"getbalance\"}'"
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
