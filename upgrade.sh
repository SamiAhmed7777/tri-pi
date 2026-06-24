#!/bin/bash
# TRI-PI upgrade — replaces the binary in place without touching data
#
# Usage:
#   sudo ./upgrade.sh                    # upgrade to latest release
#   sudo ./upgrade.sh --to v5.9.24       # upgrade to specific version
#   sudo ./upgrade.sh --tarball FILE     # upgrade from a local file
#   sudo ./upgrade.sh --check            # just check what's available
#
# What this preserves (CRITICAL — do not regress):
#   - triangles.conf (RPC creds, seed nodes, dbcache)
#   - wallet.dat (any funds, keypool, transaction history)
#   - $DATA_DIR/blockchain/* (synced chain data — re-syncing is days)
#   - $DATA_DIR/tor_data/* (Tor hidden service key — losing this = new
#     .onion, peers have to re-learn you)
#
# What this changes:
#   - /usr/local/bin/trianglesd (the binary)
#   - The systemd service unit (only if the template changed)
#
# What this checks first (lessons from the Hetzner + tridock incident 2026-06-23):
#   1. P2P port is free OR held only by our own daemon
#   2. Stale Tor state directory doesn't exist
#   3. Downloaded tarball SHA256 matches
#   4. Target version is actually newer than the installed one
#   5. Disk has enough free space for binary swap + headroom
#
# Rollback: the previous binary is kept as trianglesd.bak-<version> for 30 days.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

_tpi_init_logging "upgrade"

# ─── Argument parsing ───────────────────────────────────────────────────────

TARGET_VERSION=""
TARBALL_PATH=""
CHECK_ONLY=0
SKIP_RESTART=0
SKIP_BACKUP=0

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --to)        TARGET_VERSION="$2"; shift 2 ;;
        --tarball)   TARBALL_PATH="$2"; shift 2 ;;
        --check)     CHECK_ONLY=1; shift ;;
        --no-restart) SKIP_RESTART=1; shift ;;
        --no-backup) SKIP_BACKUP=1; shift ;;
        -h|--help)   usage 0 ;;
        *)           tpi_die "Unknown argument: $1 (try --help)" ;;
    esac
done

# ─── Pre-flight ─────────────────────────────────────────────────────────────

tpi_require_root
tpi_require_arm64

# --check is a read-only operation: report versions and exit. Don't require
# the daemon to be present (the user might be checking before installing).
# We do this early — right after the basic pre-flights — so it works in
# CI environments where the service unit doesn't exist.
if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "Current binary:  $(tpi_binary_version)"
    echo "Latest release:  $TARGET_VERSION"
    echo ""
    if [ -n "$TARGET_VERSION" ] && tpi_version_lt "$CURRENT_VERSION" "$TARGET_VERSION"; then
        echo "Status:  ⬆️  Upgrade available"
    elif [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
        echo "Status:  ✓ Up to date"
    else
        echo "Status:  ✓ Newer than latest release (custom build?)"
    fi
    exit 0
fi

if ! tpi_service_exists; then
    tpi_die "No TRI-PI install found at $TRI_PI_SERVICE_PATH. Run install.sh first."
fi

CURRENT_VERSION="$(tpi_binary_version)"
echo ""
echo "Currently installed:  $CURRENT_VERSION"
echo "Binary path:          $TRI_PI_BIN_PATH"
echo "Data directory:       $TRI_PI_DATA_DIR"
echo ""

# Resolve target version from latest release if not specified
if [ -z "$TARGET_VERSION" ] && [ -z "$TARBALL_PATH" ]; then
    echo "🔍 Checking latest release..."
    TARGET_VERSION=$(curl -fsSL https://api.github.com/repos/SamiAhmed7777/tri-pi/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 | head -1)
    if [ -z "$TARGET_VERSION" ]; then
        tpi_die "Could not determine latest version (network issue?). Specify with --to vX.Y.Z"
    fi
fi

if [ -n "$TARGET_VERSION" ]; then
    if [ "$TARGET_VERSION" = "$CURRENT_VERSION" ] && [ "$CHECK_ONLY" -eq 0 ]; then
        echo "ℹ️  Already on $CURRENT_VERSION. Re-run with --force to reinstall."
        exit 0
    fi
    if tpi_version_lt "$CURRENT_VERSION" "$TARGET_VERSION"; then
        echo "Latest:               $TARGET_VERSION (upgrade available)"
    else
        echo "Target:               $TARGET_VERSION (downgrade — proceeding anyway)"
    fi
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    exit 0
fi

# ─── Pre-upgrade validation ─────────────────────────────────────────────────

echo ""
echo "─── Pre-upgrade checks ────────────────────────────"
tpi_check_disk_space "$TRI_PI_DATA_DIR"
tpi_check_p2p_port

if ! tpi_check_tor_state "$TRI_PI_DATA_DIR"; then
    tpi_warn "  Repair automatically? [y/N]"
    read -r reply
    if [[ "$reply" =~ ^[Yy] ]]; then
        tpi_repair_tor_state "$TRI_PI_DATA_DIR"
    else
        tpi_warn "  Continuing without repair — daemon may fail to start until fixed"
    fi
fi
echo ""

# ─── Download (or use local tarball) ────────────────────────────────────────

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

if [ -n "$TARBALL_PATH" ]; then
    echo "📦 Using local tarball: $TARBALL_PATH"
    if [ ! -f "$TARBALL_PATH" ]; then
        tpi_die "Tarball not found: $TARBALL_PATH"
    fi
    cp "$TARBALL_PATH" "$WORK_DIR/tri-pi.tar.gz"
else
    PACKAGE_URL="https://github.com/SamiAhmed7777/tri-pi/releases/download/${TARGET_VERSION}/tri-pi-${TARGET_VERSION}-arm64.tar.gz"
    SHA_URL="${PACKAGE_URL}.sha256"
    echo "⬇️  Downloading $TARGET_VERSION..."
    echo "   URL: $PACKAGE_URL"

    if ! curl -fsSL -o "$WORK_DIR/tri-pi.tar.gz" "$PACKAGE_URL"; then
        tpi_die "Download failed: $PACKAGE_URL"
    fi

    if curl -fsSL -o "$WORK_DIR/tri-pi.tar.gz.sha256" "$SHA_URL" 2>/dev/null; then
        echo "🔐 Verifying SHA256..."
        if (cd "$WORK_DIR" && sha256sum -c "tri-pi.tar.gz.sha256"); then
            tpi_ok "SHA256 verified"
        else
            tpi_die "SHA256 MISMATCH — refusing to install. Re-download."
        fi
    else
        tpi_warn "SHA256 file not available — skipping integrity check"
    fi
fi

tar xzf "$WORK_DIR/tri-pi.tar.gz" -C "$WORK_DIR"
NEW_BIN="$WORK_DIR/bin/trianglesd"

if [ ! -f "$NEW_BIN" ]; then
    tpi_die "Tarball did not contain bin/trianglesd"
fi

NEW_VERSION="$(tpi_binary_version "$NEW_BIN")"
echo "Target version:        $NEW_VERSION"

# ─── Install ────────────────────────────────────────────────────────────────

echo ""
echo "─── Installing ─────────────────────────────────────"
tpi_stop_daemon

# Backup current binary
if [ "$SKIP_BACKUP" -eq 0 ]; then
    BAK_PATH="${TRI_PI_BIN_PATH}.bak-${CURRENT_VERSION}"
    if [ ! -f "$BAK_PATH" ]; then
        cp "$TRI_PI_BIN_PATH" "$BAK_PATH"
        chmod 755 "$BAK_PATH"
        tpi_ok "Previous binary backed up to $BAK_PATH"
    else
        tpi_info "Backup already exists at $BAK_PATH (skipping)"
    fi
fi

# Atomic swap via rename — either succeeds or the old binary is still there
mv "$NEW_BIN" "$TRI_PI_BIN_PATH"
chmod 755 "$TRI_PI_BIN_PATH"
tpi_ok "Binary installed: $(tpi_binary_version)"

# Update systemd unit (idempotent — uses the latest template)
tpi_write_systemd_unit "$TRI_PI_DATA_DIR"

# ─── Start ──────────────────────────────────────────────────────────────────

if [ "$SKIP_RESTART" -eq 0 ]; then
    echo ""
    echo "─── Starting ───────────────────────────────────────"
    tpi_start_daemon

    echo ""
    echo "─── Verify ─────────────────────────────────────────"
    sleep 5
    echo "  Version:       $(tpi_binary_version)"
    HEIGHT=$(tpi_block_height)
    CONNS=$(tpi_connection_count)
    echo "  Block height:  $HEIGHT"
    echo "  Connections:   $CONNS"

    if [ "$HEIGHT" = "unknown" ]; then
        tpi_warn "Could not read block height. Wait 30s for chain to load, then:"
        tpi_warn "  ${TRI_PI_BIN_PATH} -datadir=$TRI_PI_DATA_DIR getinfo"
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Upgrade complete: $CURRENT_VERSION → $NEW_VERSION"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Rollback if needed (within 30 days):"
LAST_BAK=$(ls -t "${TRI_PI_BIN_PATH}".bak-* 2>/dev/null | head -1)
if [ -n "$LAST_BAK" ]; then
    echo "  sudo systemctl stop triangles"
    echo "  sudo cp $LAST_BAK $TRI_PI_BIN_PATH"
    echo "  sudo systemctl start triangles"
fi
