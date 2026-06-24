#!/bin/bash
# TRI-PI common library — shared by install.sh, upgrade.sh, and doctor.sh
# Source this file from other scripts:  source "$(dirname "$0")/lib/common.sh"
#
# What lives here:
#   - Path/permission constants (single source of truth)
#   - User/sudo handling
#   - Systemd unit generation (DRY)
#   - Logging helpers
#   - Pre-flight checks (architecture, root, disk, ports)
#
# What does NOT live here:
#   - Network downloads (different scripts have different needs)
#   - Tor state cleanup (only needed on upgrade/repair)
#   - Bootstrap chain extract (only needed on fresh install)

set -euo pipefail

# ─── Constants ──────────────────────────────────────────────────────────────

# Install paths — change here, applies everywhere. Using :- gives priority
# to env vars set by the caller (lets tests stub out paths without root).
: "${TRI_PI_DATA_DIR:=/root/.triangles}"
: "${TRI_PI_BIN_PATH:=/usr/local/bin/trianglesd}"
: "${TRI_PI_BIN_WRAPPER:=/usr/local/bin/triangles-start-diagnostics.sh}"
: "${TRI_PI_SERVICE_PATH:=/etc/systemd/system/triangles.service}"
: "${TRI_PI_LOG_DIR:=/var/log/tri-pi}"
: "${TRI_PI_RUNTIME_LOG:=${TRI_PI_LOG_DIR}/runtime.log}"
: "${TRI_PI_SYSTEMD_STDOUT:=${TRI_PI_LOG_DIR}/systemd-stdout.log}"
: "${TRI_PI_SYSTEMD_STDERR:=${TRI_PI_LOG_DIR}/systemd-stderr.log}"

# Network — must match install.sh + bootstrap.sh + upgrade.sh
TRI_PI_P2P_PORT="${TRI_PI_P2P_PORT:-24112}"
TRI_PI_RPC_PORT="${TRI_PI_RPC_PORT:-19199}"
TRI_PI_TOR_SOCKS_PORT="${TRI_PI_TOR_SOCKS_PORT:-19099}"

# Required free disk space for install/upgrade (bytes) — 200MB covers the
# binary, the .tar.gz extraction overhead, and 2x headroom for the daemon's
# mempool/txindex growth during verification
TRI_PI_MIN_FREE_DISK_BYTES="${TRI_PI_MIN_FREE_DISK_BYTES:-209715200}"

# ─── Logging ────────────────────────────────────────────────────────────────

_tpi_init_logging() {
    local script_name="${1:-tri-pi}"
    mkdir -p "$TRI_PI_LOG_DIR"
    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    TPI_LOG_FILE="${TRI_PI_LOG_DIR}/${script_name}-${stamp}.log"
    # Send all subsequent output to both terminal and log file
    exec > >(tee -a "$TPI_LOG_FILE") 2>&1
    echo "═══════════════════════════════════════════════════════════════"
    echo "  $script_name started at $(date -Iseconds)"
    echo "  Log: $TPI_LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════"
}

# ─── Pre-flight ─────────────────────────────────────────────────────────────

tpi_die() {
    echo "❌ $*" >&2
    exit 1
}

tpi_warn() {
    echo "⚠️  $*" >&2
}

tpi_ok() {
    echo "✓ $*"
}

tpi_info() {
    echo "  $*"
}

tpi_require_root() {
    if [ "$(id -u)" != "0" ]; then
        tpi_die "This script must be run as root. Re-run with: sudo $0"
    fi
}

tpi_require_arm64() {
    local arch
    arch=$(uname -m)
    if [ "$arch" != "aarch64" ]; then
        tpi_die "TRI-PI is for ARM64 (aarch64) only — detected: $arch"
    fi
}

tpi_check_disk_space() {
    local data_dir="$1"
    local free_bytes
    free_bytes=$(df -PB1 "$data_dir" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -z "$free_bytes" ] || [ "$free_bytes" -lt "$TRI_PI_MIN_FREE_DISK_BYTES" ]; then
        tpi_die "Need at least $(numfmt --to=iec "$TRI_PI_MIN_FREE_DISK_BYTES") free in $data_dir (have: ${free_bytes:-0} bytes)"
    fi
    tpi_ok "Disk space OK ($(numfmt --to=iec "$free_bytes") free)"
}

# Check whether the P2P port is free or already bound by our own daemon
tpi_check_p2p_port() {
    local state
    state=$(ss -tlnp 2>/dev/null | grep -E ":${TRI_PI_P2P_PORT}\b" || true)
    if [ -n "$state" ]; then
        # Is the bound process our own trianglesd? If so, fine.
        if echo "$state" | grep -q trianglesd; then
            tpi_info "P2P port ${TRI_PI_P2P_PORT} already bound by trianglesd (expected during upgrade)"
            return 0
        fi
        # Otherwise it's another process (commonly: stale Tor after a failed start)
        local holder
        holder=$(echo "$state" | grep -oE 'users:\(\("[^"]+"' | head -1 | tr -d '"' | cut -d'(' -f2)
        tpi_die "P2P port ${TRI_PI_P2P_PORT} held by another process: $holder

This is almost always stale Tor from a prior failed start. Fix with:
  sudo lsof -i :${TRI_PI_P2P_PORT}  # see what's holding it
  sudo kill -9 <pid>                  # kill it
Then re-run this script."
    fi
    tpi_ok "P2P port ${TRI_PI_P2P_PORT} is free"
}

# Check the Tor DataDirectory state — known failure mode (see tri-pi issue log
# 2026-06-23: stale directory at $DATA_DIR/tor_data/state breaks Tor startup
# with 'State file is not a file' error)
tpi_check_tor_state() {
    local data_dir="$1"
    local state_path="${data_dir}/tor_data/state"
    if [ -d "$state_path" ] && [ -n "$(ls -A "$state_path" 2>/dev/null)" ]; then
        tpi_warn "Tor DataDirectory is a non-empty directory: $state_path"
        tpi_warn "  This is a known cause of 'Tor failed to start' on first boot."
        return 1
    fi
    tpi_ok "Tor state clean"
    return 0
}

tpi_repair_tor_state() {
    local data_dir="$1"
    local state_path="${data_dir}/tor_data/state"
    if [ -d "$state_path" ]; then
        echo "  Removing stale tor state directory: $state_path"
        rm -rf "$state_path"
        tpi_ok "Tor state repaired"
    fi
}

# ─── Systemd unit generation ───────────────────────────────────────────────

# Generate the systemd service unit with the right ExecStart wiring. Idempotent.
# $1 = path to data directory
tpi_write_systemd_unit() {
    local data_dir="$1"

    # Wrapper script — the actual thing systemd runs. Sends all daemon output
    # to the runtime log so it survives journal rotation.
    cat > "$TRI_PI_BIN_WRAPPER" <<WRAPPER
#!/bin/bash
set -euo pipefail
DATA_DIR="${data_dir}"
LOG_DIR="${TRI_PI_LOG_DIR}"
mkdir -p "\$LOG_DIR"
exec "${TRI_PI_BIN_PATH}" -daemon=0 -datadir="\$DATA_DIR" >> "${TRI_PI_RUNTIME_LOG}" 2>&1
WRAPPER
    chmod 755 "$TRI_PI_BIN_WRAPPER"

    # Service unit
    cat > "$TRI_PI_SERVICE_PATH" <<UNIT
[Unit]
Description=Triangles Cryptocurrency Node (TRI-PI)
Documentation=https://github.com/SamiAhmed7777/tri-pi
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=${TRI_PI_BIN_WRAPPER}
ExecStop=${TRI_PI_BIN_PATH} -datadir=${data_dir} stop
Restart=on-failure
RestartSec=30
TimeoutStopSec=120
LimitNOFILE=65536
StandardOutput=append:${TRI_PI_SYSTEMD_STDOUT}
StandardError=append:${TRI_PI_SYSTEMD_STDERR}

# Hardening — TRI is a privacy coin; least-privilege applies
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    tpi_ok "Systemd unit installed at $TRI_PI_SERVICE_PATH"
}

# ─── Config management ──────────────────────────────────────────────────────

# Write a default triangles.conf. Only called when no config exists — never
# overwrites a user's existing one.
tpi_write_default_config() {
    local data_dir="$1"
    local version="$2"
    local rpc_pass
    rpc_pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)

    cat > "${data_dir}/triangles.conf" <<CONFIG
# TRI-PI ${version} Configuration — generated $(date -Iseconds)
# Edit this file carefully; the daemon reads it on every start.

server=1
listen=1

# RPC (localhost only)
rpcuser=tripi
rpcpassword=${rpc_pass}
rpcallowip=127.0.0.1
rpcport=${TRI_PI_RPC_PORT}

# P2P
port=${TRI_PI_P2P_PORT}
maxconnections=50

# Performance — tuned for ARM/Pi memory budget
dbcache=100
maxmempool=50

# Seed nodes (DNS2/DNS3/Hetzner — Tor-capable)
addnode=194.233.88.206
addnode=74.208.167.19
addnode=179.189.35.51
CONFIG
    chmod 600 "${data_dir}/triangles.conf"
    tpi_ok "Configuration created at ${data_dir}/triangles.conf"
    tpi_warn "RPC password: ${rpc_pass}  (save this — only stored in triangles.conf)"
}

# ─── Lifecycle helpers ──────────────────────────────────────────────────────

tpi_service_active() {
    systemctl is-active --quiet triangles 2>/dev/null
}

tpi_service_exists() {
    [ -f "$TRI_PI_SERVICE_PATH" ]
}

tpi_stop_daemon() {
    if tpi_service_active; then
        tpi_info "Stopping triangles service..."
        systemctl stop triangles
        sleep 3
    fi
    # Belt-and-braces — kill any leftover trianglesd (only our own binary path;
    # we never pkill the bare process name since it could match tridock too)
    local stale_pids
    stale_pids=$(pgrep -f "${TRI_PI_BIN_PATH}.*datadir=${TRI_PI_DATA_DIR}" || true)
    if [ -n "$stale_pids" ]; then
        tpi_info "Killing stale daemon: $stale_pids"
        echo "$stale_pids" | xargs -r kill -9 || true
        sleep 1
    fi
}

tpi_start_daemon() {
    systemctl enable triangles >/dev/null 2>&1 || true
    systemctl start triangles
    sleep 2
    if tpi_service_active; then
        tpi_ok "Daemon running"
    else
        tpi_warn "Service did not start cleanly. Check:"
        tpi_warn "  journalctl -u triangles -n 50"
        tpi_warn "  tail -f ${TRI_PI_SYSTEMD_STDERR}"
    fi
}

# ─── Version helpers ────────────────────────────────────────────────────────

# Read the version string baked into the running binary. Works even when the
# data dir is locked (which blocks `trianglesd --version`).
tpi_binary_version() {
    local bin_path="${1:-$TRI_PI_BIN_PATH}"
    strings "$bin_path" 2>/dev/null | grep -oE 'v5\.[0-9]+\.[0-9]+' | head -1 || echo "unknown"
}

# Read the current block height via getinfo. Requires the daemon to be up.
tpi_block_height() {
    "${TRI_PI_BIN_PATH}" -datadir="$TRI_PI_DATA_DIR" getinfo 2>/dev/null \
        | grep -oE '"blocks"[[:space:]]*:[[:space:]]*[0-9]+' \
        | grep -oE '[0-9]+' || echo "unknown"
}

# Read the network connection count
tpi_connection_count() {
    "${TRI_PI_BIN_PATH}" -datadir="$TRI_PI_DATA_DIR" getinfo 2>/dev/null \
        | grep -oE '"connections"[[:space:]]*:[[:space:]]*[0-9]+' \
        | grep -oE '[0-9]+' || echo "unknown"
}

# Compare two semver-ish strings (v5.9.20 vs v5.9.24). Returns 0 if a < b.
tpi_version_lt() {
    local a="${1#v}" b="${2#v}"
    [ "$a" != "$b" ] && [ "$a" = "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" ]
}
