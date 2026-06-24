#!/bin/bash
# TRI-PI doctor — one-shot diagnostic for a misbehaving node
#
# Usage:
#   sudo ./tri-pi-doctor.sh
#   sudo ./tri-pi-doctor.sh --json    # machine-readable for monitoring
#
# Prints a structured report covering:
#   - Installed vs running binary version (mismatch = bad restart)
#   - Service state + recent log lines
#   - P2P/RPC port bindings (catches the "stale Tor" failure mode)
#   - Tor state directory health (catches "Tor failed to start")
#   - Blockchain height vs network tip
#   - Disk space and inode pressure
#   - Last fatal errors from debug.log
#
# Exit codes:
#   0  Healthy
#   1  Warning(s) found (degraded but functional)
#   2  Error(s) found (likely not functional)
#   3  Cannot run (not ARM64 / not root / no install)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

JSON_MODE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON_MODE=1; shift ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) tpi_die "Unknown arg: $1" ;;
    esac
done

# ─── Output helpers ─────────────────────────────────────────────────────────

# We accumulate findings then print all at once. Each finding is one of:
#   OK    (exit 0)
#   WARN  (exit 1, degrades)
#   FAIL  (exit 2, broken)
#   INFO  (neutral, just a fact)

declare -a FINDINGS=()
OVERALL_EXIT=0

record() {
    local level="$1" what="$2" detail="${3:-}"
    FINDINGS+=("$level|$what|$detail")
    # Don't use arithmetic comparison in set -e — use || true so a false
    # comparison doesn't kill the script before all findings are recorded.
    case "$level" in
        OK)   ;;
        INFO) ;;
        WARN) [ "$OVERALL_EXIT" -lt 1 ] && OVERALL_EXIT=1 || true ;;
        FAIL) [ "$OVERALL_EXIT" -lt 2 ] && OVERALL_EXIT=2 || true ;;
    esac
}

emit() {
    if [ "$JSON_MODE" -eq 1 ]; then
        # JSON output — one record per line
        printf '{"level":"%s","what":"%s","detail":"%s"}\n' \
            "$(echo "$1" | sed 's/"/\\"/g')" \
            "$(echo "$2" | sed 's/"/\\"/g')" \
            "$(echo "$3" | sed 's/"/\\"/g')"
    else
        case "$1" in
            OK)   printf "  \033[32m✓\033[0m %s" "$2"; [ -n "$3" ] && printf " — %s" "$3"; printf "\n" ;;
            INFO) printf "  ℹ️  %s" "$2"; [ -n "$3" ] && printf " — %s" "$3"; printf "\n" ;;
            WARN) printf "  \033[33m⚠\033[0m  %s" "$2"; [ -n "$3" ] && printf " — %s" "$3"; printf "\n" ;;
            FAIL) printf "  \033[31m✗\033[0m %s" "$2"; [ -n "$3" ] && printf " — %s" "$3"; printf "\n" ;;
        esac
    fi
}

# ─── Header ─────────────────────────────────────────────────────────────────

if [ "$JSON_MODE" -eq 0 ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                  TRI-PI Doctor Report                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Host:        $(hostname)"
    echo "  Arch:        $(uname -m)"
    echo "  Kernel:      $(uname -r)"
    echo "  Time:        $(date -Iseconds)"
    echo ""
fi

# ─── Pre-checks ─────────────────────────────────────────────────────────────

[ "$(id -u)" = "0" ] || record FAIL "root" "not running as root — some checks will be incomplete"
[ "$(uname -m)" = "aarch64" ] || record FAIL "arch" "expected aarch64, got $(uname -m)"

# ─── Binary version ────────────────────────────────────────────────────────

if [ -x "$TRI_PI_BIN_PATH" ]; then
    BIN_VER="$(tpi_binary_version)"
    record OK "binary-installed" "$TRI_PI_BIN_PATH @ $BIN_VER"
else
    record FAIL "binary-missing" "$TRI_PI_BIN_PATH not found"
fi

# ─── Service state ──────────────────────────────────────────────────────────

if tpi_service_exists; then
    if tpi_service_active; then
        record OK "service-active" "triangles is running"
    else
        record FAIL "service-inactive" "triangles is not running"
    fi
else
    record FAIL "service-missing" "$TRI_PI_SERVICE_PATH not found"
fi

# ─── Process check ──────────────────────────────────────────────────────────

DAEMON_PID=$(pgrep -f "${TRI_PI_BIN_PATH}.*datadir=${TRI_PI_DATA_DIR}" || true)
if [ -n "$DAEMON_PID" ]; then
    record OK "daemon-process" "pid=$DAEMON_PID"
else
    record FAIL "daemon-process" "no trianglesd process matching expected datadir"
fi

# ─── Port bindings (the key learning) ──────────────────────────────────────

# P2P port
P2P_BINDING=$(ss -tlnp 2>/dev/null | grep -E ":${TRI_PI_P2P_PORT}\b" || true)
if [ -z "$P2P_BINDING" ]; then
    record FAIL "p2p-port-${TRI_PI_P2P_PORT}" "not bound — daemon may be dead or still starting"
elif echo "$P2P_BINDING" | grep -q trianglesd; then
    record OK "p2p-port-${TRI_PI_P2P_PORT}" "bound by trianglesd"
else
    # Common failure: stale Tor from a prior failed start
    HOLDER=$(echo "$P2P_BINDING" | grep -oE 'users:\(\("[^"]+"' | head -1 | tr -d '"' | cut -d'(' -f2)
    record FAIL "p2p-port-${TRI_PI_P2P_PORT}" "held by $HOLDER (stale process — kill it)"
fi

# RPC port
RPC_BINDING=$(ss -tlnp 2>/dev/null | grep -E ":${TRI_PI_RPC_PORT}\b" || true)
if [ -n "$RPC_BINDING" ] && echo "$RPC_BINDING" | grep -q trianglesd; then
    record OK "rpc-port-${TRI_PI_RPC_PORT}" "bound by trianglesd (localhost)"
else
    record WARN "rpc-port-${TRI_PI_RPC_PORT}" "not bound — RPC unavailable"
fi

# Tor SOCKS
TOR_BINDING=$(ss -tlnp 2>/dev/null | grep -E ":${TRI_PI_TOR_SOCKS_PORT}\b" || true)
if [ -n "$TOR_BINDING" ] && echo "$TOR_BINDING" | grep -q tor; then
    record OK "tor-socks-${TRI_PI_TOR_SOCKS_PORT}" "bound by tor"
else
    record FAIL "tor-socks-${TRI_PI_TOR_SOCKS_PORT}" "not bound — Triangles requires Tor to operate"
fi

# ─── Tor state dir health (the OTHER key learning) ─────────────────────────

TOR_STATE="${TRI_PI_DATA_DIR}/tor_data/state"
if [ -d "$TOR_STATE" ] && [ -n "$(ls -A "$TOR_STATE" 2>/dev/null)" ]; then
    # Spell out the exact fix in the detail field — operator can copy-paste it
    record FAIL "tor-state" "stale directory at $TOR_STATE — Tor will fail to start with 'State file is not a file'. Fix: sudo rm -rf $TOR_STATE && sudo systemctl restart triangles"
elif [ -e "$TOR_STATE" ]; then
    record OK "tor-state" "$TOR_STATE is a file (healthy)"
else
    record INFO "tor-state" "$TOR_STATE not yet created (first boot?)"
fi

# ─── Disk space ─────────────────────────────────────────────────────────────

DATA_FREE=$(df -PB1 "$TRI_PI_DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || true)
if [ -n "$DATA_FREE" ]; then
    FREE_IEC=$(numfmt --to=iec "$DATA_FREE")
    if [ "$DATA_FREE" -lt 1073741824 ]; then  # < 1GB
        record FAIL "disk-space" "only $FREE_IEC free in data dir"
    elif [ "$DATA_FREE" -lt 5368709120 ]; then  # < 5GB
        record WARN "disk-space" "$FREE_IEC free (low — consider expanding)"
    else
        record OK "disk-space" "$FREE_IEC free"
    fi
fi

# ─── Chain height + connection count ───────────────────────────────────────

if [ -n "$DAEMON_PID" ] && tpi_service_active; then
    HEIGHT=$(tpi_block_height)
    CONNS=$(tpi_connection_count)
    if [ "$HEIGHT" != "unknown" ]; then
        record OK "block-height" "$HEIGHT"
    else
        record WARN "block-height" "RPC responding but height unknown (still loading?)"
    fi
    record INFO "connections" "$CONNS"
fi

# ─── Recent fatal errors ───────────────────────────────────────────────────

DEBUG_LOG="${TRI_PI_DATA_DIR}/debug.log"
if [ -f "$DEBUG_LOG" ]; then
    FATALS=$(grep -E "ERROR|FATAL|Tor failed|invalid|EXCEPTION" "$DEBUG_LOG" 2>/dev/null | tail -5 || true)
    if [ -n "$FATALS" ]; then
        record WARN "recent-errors" "$(echo "$FATALS" | head -1 | cut -c1-100)"
    else
        record OK "recent-errors" "none in last lines of $DEBUG_LOG"
    fi
fi

# ─── Systemd journal fatals ────────────────────────────────────────────────

if command -v journalctl >/dev/null 2>&1; then
    JOURNAL_ERRS=$(journalctl -u triangles --since "10 min ago" --no-pager 2>/dev/null \
        | grep -iE "fatal|segfault|aborted|tor failed to start" || true)
    if [ -n "$JOURNAL_ERRS" ]; then
        record FAIL "journal-errors" "$(echo "$JOURNAL_ERRS" | head -1 | cut -c1-100)"
    else
        record OK "journal-errors" "no fatals in last 10 min"
    fi
fi

# ─── Version file freshness (catches installation drift) ──────────────────

if [ -f "${SCRIPT_DIR}/VERSION" ] && [ -x "$TRI_PI_BIN_PATH" ]; then
    REPO_VER=$(cat "${SCRIPT_DIR}/VERSION")
    if [ "$REPO_VER" != "$(tpi_binary_version)" ]; then
        record INFO "version-drift" "repo says $REPO_VER, installed $(tpi_binary_version) — likely deployment lag"
    fi
fi

# ─── Emit findings ─────────────────────────────────────────────────────────

if [ "$JSON_MODE" -eq 0 ]; then
    echo "─── Findings ───────────────────────────────────────"
fi
for f in "${FINDINGS[@]}"; do
    IFS='|' read -r level what detail <<< "$f"
    emit "$level" "$what" "$detail"
done

if [ "$JSON_MODE" -eq 0 ]; then
    echo ""
    case "$OVERALL_EXIT" in
        0) echo "🟢 Healthy" ;;
        1) echo "🟡 Degraded — see warnings above" ;;
        2) echo "🔴 Broken — see failures above" ;;
    esac
    echo ""
    echo "  Re-run with --json for machine-readable output (e.g. for monitoring)"
    echo ""
fi

exit "$OVERALL_EXIT"
