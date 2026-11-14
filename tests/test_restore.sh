#!/bin/bash
# TRI-PI restore-safety behavioral tests — executable proof, not grep checks.
# Exercises tpi_validate_archive / tpi_stage_restore / tpi_write_marker /
# tpi_restore_recover / do_restore from tri7-appliance:
#   1. valid archive -> accepted, staged at the right path, wallet preserved
#   2. corrupt archive -> refused
#   3. absolute path -> refused (fixture verified)
#   4. .. traversal -> refused (fixture verified)
#   5. sibling member -> refused
#   6. symlink member -> refused
#   7. hardlink member -> refused
#   8. do_restore end-to-end: placement, backup retention, service calls
#   9. corrupt input refused before any swap; live data preserved
#  10. crash AFTER first mv: recovery rolls back to known-good data
#  11. crash BEFORE first mv: stale marker cleaned, live data intact
#  12. FAULT INJECTION: first mv fails (marker fsynced first; live intact)
#  13. FAULT INJECTION: second mv fails (rollback restores original, marker cleaned)
set -uo pipefail
PASS=0; FAIL=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export TRI_PI_DATA_DIR="$WORK/home/.triangles"
mkdir -p "$TRI_PI_DATA_DIR" "$WORK/home" "$WORK/stage-parent"
echo "wallet-bytes" > "$TRI_PI_DATA_DIR/wallet.dat"

# Source the WHOLE appliance script (its sourcing guard skips the CLI dispatch)
# so every function is defined exactly as shipped — no sed-fragment fragility.
set +e
. ./tri7-appliance
set -uo pipefail

# ── 1. valid archive round-trip ──
GOOD="$WORK/good.tgz"
tar -czf "$GOOD" -C "$(dirname "$TRI_PI_DATA_DIR")" "$(basename "$TRI_PI_DATA_DIR")"
if tpi_validate_archive "$GOOD" > /dev/null 2>&1; then
    pass "valid archive accepted by validator"
else
    fail "valid archive REFUSED by validator"
fi
STAGED="$(tpi_stage_restore "$GOOD" "$WORK/stage-parent" 2>/dev/null || true)"
if [ -f "$STAGED/wallet.dat" ] && [ "$(cat "$STAGED/wallet.dat")" = "wallet-bytes" ]; then
    pass "staged restore places wallet under basename(TRI_PI_DATA_DIR)"
else
    fail "staged restore misplaced or lost the wallet"
fi

# ── 2. corrupt archive ──
CORRUPT="$WORK/corrupt.tgz"; echo "not-a-tar" > "$CORRUPT"
tpi_validate_archive "$CORRUPT" > /dev/null 2>&1 && fail "corrupt archive ACCEPTED" || pass "corrupt archive refused"

# ── 3. absolute path member (created with -P so the leading / is STORED) ──
ABS="$WORK/abs.tgz"; mkdir -p "$WORK/payload" && echo x > "$WORK/payload/evil"
tar -czf "$ABS" -P -C / "$(echo "$WORK/payload/evil")" 2>/dev/null
if tar -tzf "$ABS" 2>/dev/null | grep -qE '^/'; then
    # fixture verified: a member with a leading / is really stored
    tpi_validate_archive "$ABS" > /dev/null 2>&1 && fail "absolute-path archive ACCEPTED" || pass "absolute-path archive refused (fixture verified)"
else
    fail "fixture broken: tar did not store an absolute-path member"
fi

# ── 4. .. traversal member (-P keeps the .. in the stored member) ──
DOTDOT="$WORK/dotdot.tgz"
mkdir -p "$WORK/evilpkg/.triangles" && echo x > "$WORK/evilpkg/.triangles/x"
( cd "$WORK/evilpkg" && tar -czf "$DOTDOT" -P --transform 's|^|../|' ".triangles" ) 2>/dev/null
if tar -tzf "$DOTDOT" 2>/dev/null | grep -qE '(^|/)\.\.(/|$)'; then
    tpi_validate_archive "$DOTDOT" > /dev/null 2>&1 && fail ".. archive ACCEPTED" || pass ".. traversal archive refused (fixture verified)"
else
    fail "fixture broken: tar did not store a .. member"
fi

# ── 5. sibling member (outside the data dir) ──
SIB="$WORK/sib.tgz"
mkdir -p "$WORK/sibpack/evil" && echo x > "$WORK/sibpack/evil/x"
tar -czf "$SIB" -C "$WORK/sibpack" evil
tpi_validate_archive "$SIB" > /dev/null 2>&1 && fail "sibling-member archive ACCEPTED" || pass "sibling-member archive refused"

# ── 6. symlink member ──
LINK="$WORK/link.tgz"
mkdir -p "$WORK/linkpkg/.triangles" "$WORK/linktarget" && echo x > "$WORK/linktarget/x"
ln -s ../../linktarget "$WORK/linkpkg/.triangles/escape"
tar -czf "$LINK" -C "$WORK/linkpkg" .triangles   # WITHOUT -h: link stored as a link
if tar -tvzf "$LINK" 2>/dev/null | awk '$1 ~ /^l/ {found=1} END {exit !found}'; then
    tpi_validate_archive "$LINK" > /dev/null 2>&1 && fail "symlink archive ACCEPTED" || pass "symlink-member archive refused"
else
    fail "fixture broken: tar did not store the symlink as a link member"
fi

# ── 7. FIFO member ──
FIFO="$WORK/fifo.tgz"
mkdir -p "$WORK/fifopkg/.triangles" && mkfifo "$WORK/fifopkg/.triangles/pipe" 2>/dev/null
if [ -p "$WORK/fifopkg/.triangles/pipe" ]; then
    tar -czf "$FIFO" -C "$WORK/fifopkg" .triangles
    if tar -tvzf "$FIFO" 2>/dev/null | awk '$1 ~ /^p/ {found=1} END {exit !found}'; then
        tpi_validate_archive "$FIFO" > /dev/null 2>&1 && fail "FIFO archive ACCEPTED" || pass "FIFO-member archive refused"
    else
        fail "fixture broken: tar did not store the FIFO as a special member"
    fi
else
    pass "FIFO test skipped (mkfifo unavailable)"
fi

# ── 7. hardlink member ──
HL="$WORK/hl.tgz"
mkdir -p "$WORK/hlpkg/.triangles" && echo x > "$WORK/hlpkg/.triangles/real" && ln "$WORK/hlpkg/.triangles/real" "$WORK/hlpkg/.triangles/hard" 2>/dev/null
if [ -e "$WORK/hlpkg/.triangles/hard" ]; then
    tar -czf "$HL" -C "$WORK/hlpkg" .triangles
    if tar -tvzf "$HL" 2>/dev/null | awk '$1 ~ /^h/ {found=1} END {exit !found}'; then
        tpi_validate_archive "$HL" > /dev/null 2>&1 && fail "hardlink archive ACCEPTED" || pass "hardlink-member archive refused"
    else
        fail "fixture broken: tar stored hardlinks as regular files"
    fi
else
    pass "hardlink test skipped (filesystem does not support hardlinks here)"
fi

# ── 8. do_restore end-to-end: success placement + backup retention + service calls ──
SVC_LOG="$WORK/svc.log"
export TRI_PI_SVC_MODE=fake TRI_PI_SVC_LOG="$SVC_LOG"
E2E_PARENT="$(dirname "$TRI_PI_DATA_DIR")"
# place a live wallet, then restore over it
echo live-old > "$TRI_PI_DATA_DIR/wallet.dat"
if OUT="$(do_restore "$GOOD")"; then
    if [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat")" = "wallet-bytes" ]; then
        pass "do_restore places restored wallet at TRI_PI_DATA_DIR"
    else
        fail "do_restore wrong content at TRI_PI_DATA_DIR"
    fi
    if ls -d "$E2E_PARENT"/.triangles.pre-restore-* > /dev/null 2>&1; then
        pass "do_restore retains the pre-restore backup dir"
    else
        fail "pre-restore backup dir missing"
    fi
    if [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat" 2>/dev/null)" = "wallet-bytes" ] && grep -q fake-stop "$SVC_LOG" && grep -q fake-start "$SVC_LOG"; then
        pass "do_restore stops and starts the service (fake mode verified)"
    else
        fail "service stop/start not observed"
    fi
    [ -f "$E2E_PARENT/.triangles.restore-marker" ] && fail "restore marker left behind" || pass "restore marker cleaned up"
else
    fail "do_restore failed end-to-end: $OUT"
fi

# ── 9. corrupt input refused before any swap; live data preserved ──
echo live-rollback > "$TRI_PI_DATA_DIR/wallet.dat"
if ! tpi_stage_restore "$CORRUPT" "$E2E_PARENT" > /dev/null 2>&1; then
    pass "stage_restore refuses corrupt archive before any swap (no live-data risk)"
else
    fail "stage_restore accepted corrupt archive"
fi
if [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat")" = "live-rollback" ]; then
    pass "live wallet untouched after refused restore"
else
    fail "live wallet modified by refused restore"
fi

# ── 12-14. FAULT INJECTION via an mv() function override — deterministic
# (no PATH/hash games). Rename sequence inside do_restore:
#   call 1 = marker tmp->path, call 2 = current->backup,
#   call 3 = staged->current, call 4 = rollback backup->current.
MV_CALLS_FILE="$WORK/mv-calls"
FAIL_CALLS=""   # space-separated rename positions to fail (1..4)
mv() {  # test-only override of mv, used by do_restore under injection.
        # File-based counter: do_restore runs in a subshell, so the count
        # must be visible to the parent's assertions.
    local n
    n=$(cat "$MV_CALLS_FILE" 2>/dev/null || echo 0)
    n=$((n+1))
    echo "$n" > "$MV_CALLS_FILE"
    case " $FAIL_CALLS " in
        *" $n "*) return 1 ;;
    esac
    /bin/mv "$@"
}
calls() { cat "$MV_CALLS_FILE" 2>/dev/null || echo 0; }

# ── 12. marker rename fails -> swap refused, live intact ──
echo live-fault1 > "$TRI_PI_DATA_DIR/wallet.dat"
FAIL_CALLS="1"; rm -rf "$MV_CALLS_FILE" "$E2E_PARENT"/.triangles.pre-restore-* "$E2E_PARENT"/.triangles.restore-marker 2>/dev/null
if OUT="$(do_restore "$GOOD" 2>&1)"; then
    fail "do_restore did not surface the marker-write failure"
else
    pass "do_restore refuses the swap when the marker rename fails (call 1)"
fi
if [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat")" = "live-fault1" ]; then
    pass "live data intact after marker-write failure"
else
    fail "live data disturbed by marker-write failure"
fi
if [ "$(calls)" = "1" ]; then
    pass "no further renames attempted after marker failure (call count = 1)"
else
    fail "renames continued past the failed marker write (calls: $(calls))"
fi

# ── 13. current->backup rename fails -> live data intact ──
echo live-fault2 > "$TRI_PI_DATA_DIR/wallet.dat"
FAIL_CALLS="2"; rm -rf "$MV_CALLS_FILE" "$E2E_PARENT"/.triangles.pre-restore-* "$E2E_PARENT"/.triangles.restore-marker 2>/dev/null
if OUT="$(do_restore "$GOOD" 2>&1)"; then
    fail "do_restore did not surface the current->backup failure"
else
    pass "do_restore refuses the swap when current->backup fails (call 2)"
fi
if [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat")" = "live-fault2" ]; then
    pass "live data intact after current->backup failure"
else
    fail "live data disturbed by current->backup failure"
fi
tpi_restore_recover 2>/dev/null
[ -f "$E2E_PARENT/.triangles.restore-marker" ] && fail "stale marker not cleaned" || pass "stale marker cleaned after current->backup failure"

# ── 14. staged->current rename fails -> full rollback via call 4 ──
echo live-original > "$TRI_PI_DATA_DIR/wallet.dat"
FAIL_CALLS="3"; rm -rf "$MV_CALLS_FILE" "$E2E_PARENT"/.triangles.pre-restore-* "$E2E_PARENT"/.triangles.restore-marker 2>/dev/null
if OUT="$(do_restore "$GOOD" 2>&1)"; then
    fail "do_restore did not surface the staged->current failure"
else
    pass "do_restore fails loudly when staged->current fails (call 3)"
fi
if [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat")" = "live-original" ]; then
    pass "rollback restored the ORIGINAL live data (call 4: backup->current)"
else
    fail "rollback lost the original live data (got: $(cat "$TRI_PI_DATA_DIR/wallet.dat" 2>/dev/null))"
fi
[ -f "$E2E_PARENT/.triangles.restore-marker" ] && fail "marker left after rollback" || pass "marker cleaned after rollback"
if [ "$(calls)" = "4" ]; then
    pass "full rename sequence verified (4 calls: marker, aside, install, rollback)"
else
    fail "unexpected rename sequence (calls: $(calls))"
fi

# ── 15. FAULT INJECTION: rollback (call 4) ALSO fails -> honest degraded state ──
echo live-orig-2 > "$TRI_PI_DATA_DIR/wallet.dat"
FAIL_CALLS="3 4"; rm -rf "$MV_CALLS_FILE" "$E2E_PARENT"/.triangles.pre-restore-* "$E2E_PARENT"/.triangles.restore-marker 2>/dev/null
if OUT="$(do_restore "$GOOD" 2>&1)"; then
    fail "do_restore did not surface the double-rename failure"
else
    pass "do_restore fails loudly when BOTH staged install and rollback fail (calls 3+4)"
fi
if [ "$(echo "$OUT" | grep -c 'CRITICAL')" -ge 1 ] && [ "$(echo "$OUT" | grep -c 'NOT in place')" -ge 1 ]; then
    pass "degraded state reported honestly (no false 'untouched' claim)"
else
    fail "double-failure reporting not honest: $OUT"
fi
if [ -f "$E2E_PARENT/.triangles.restore-marker" ]; then
    pass "recovery metadata RETAINED after double failure (recovery remains possible)"
else
    fail "marker discarded — double-failure state unrecoverable"
fi
tpi_restore_recover
if [ -d "$TRI_PI_DATA_DIR" ] && [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat")" = "live-orig-2" ]; then
    pass "post-double-failure recovery completes from the retained backup"
else
    fail "recovery could not complete after double failure"
fi
[ -f "$E2E_PARENT/.triangles.restore-marker" ] && fail "marker left after recovery" || pass "marker cleaned after recovery"

unset -f mv

# ── 16. SUBPROCESS proof: the DOCUMENTED recovery procedure works — running
# any tri7-appliance CLI command (subprocess, not a direct function call)
# auto-recovers the interrupted-restore state.
echo live-cli > "$TRI_PI_DATA_DIR/wallet.dat"
BK2="$E2E_PARENT/.triangles.pre-cli"
mv "$TRI_PI_DATA_DIR" "$BK2"
echo "$BK2" > "$E2E_PARENT/.triangles.restore-marker"
CLI_OUT="$(TRI_PI_SVC_MODE=fake TRI_PI_SVC_LOG="$WORK/svc2.log" \
    TRI_PI_DATA_DIR="$TRI_PI_DATA_DIR" bash tri7-appliance status 2>&1)"
if [ -d "$TRI_PI_DATA_DIR" ] && [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat" 2>/dev/null)" = "live-cli" ]; then
    pass "running 'tri7-appliance status' as a subprocess auto-recovers the data dir"
else
    fail "CLI startup did not recover the interrupted-restore state: $CLI_OUT"
fi
[ -f "$E2E_PARENT/.triangles.restore-marker" ] && fail "CLI recovery left the marker" || pass "CLI recovery cleaned the marker"

# ── 10. crash recovery — AFTER the first mv (current gone, backup + marker) ──
echo live-crash > "$TRI_PI_DATA_DIR/wallet.dat"
BK="$E2E_PARENT/.triangles.pre-crash"
mv "$TRI_PI_DATA_DIR" "$BK"
echo "$BK" > "$E2E_PARENT/.triangles.restore-marker"
tpi_restore_recover
if [ -d "$TRI_PI_DATA_DIR" ] && [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat")" = "live-crash" ]; then
    pass "crash recovery rolls back to the known-good data dir"
else
    fail "crash recovery failed to restore the data dir"
fi
[ -f "$E2E_PARENT/.triangles.restore-marker" ] && fail "recovery left the marker" || pass "recovery cleaned the marker"

# ── 11. crash BEFORE the first mv (marker written, current still intact) ──
# this is the state right after the durable marker write, before renames
echo live-safe > "$TRI_PI_DATA_DIR/wallet.dat"
echo "$E2E_PARENT/.triangles.never-happened" > "$E2E_PARENT/.triangles.restore-marker"
tpi_restore_recover
if [ -d "$TRI_PI_DATA_DIR" ] && [ "$(cat "$TRI_PI_DATA_DIR/wallet.dat")" = "live-safe" ]; then
    pass "stale pre-rename marker leaves live data intact"
else
    fail "stale marker handling disturbed live data"
fi
[ -f "$E2E_PARENT/.triangles.restore-marker" ] && fail "stale marker not cleaned" || pass "stale marker cleaned"

echo ""
echo "====================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "====================================="
[ "$FAIL" -ne 0 ] && exit 1
exit 0
