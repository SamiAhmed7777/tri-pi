#!/bin/bash
# TRI-PI installer tests — paths relative to repo root, no hardcoded /root/tri-pi

set -uo pipefail

PASS=0
FAIL=0

pass() { echo "  ✓ $*"; ((PASS++)) || true; }
fail() { echo "  ✗ $*"; ((FAIL++)) || true; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Test 1: install.sh exists
echo "=== Test: install.sh exists ==="
[ -f install.sh ] && pass "install.sh exists" || fail "install.sh missing"

# Test 2: bootstrap.sh exists
echo "=== Test: bootstrap.sh exists ==="
[ -f bootstrap.sh ] && pass "bootstrap.sh exists" || fail "bootstrap.sh missing"

# Test 3: VERSION file exists
echo "=== Test: VERSION file exists ==="
[ -f VERSION ] && pass "VERSION file exists" || fail "VERSION file missing"

# Test 4: install.sh has ARM64 check
echo "=== Test: install.sh ARM64 check ==="
grep -qE "aarch64|arm64" install.sh 2>/dev/null && pass "ARM64 check present" || fail "ARM64 check missing"

# Test 5: install.sh has apt-get
echo "=== Test: install.sh apt-get ==="
grep -q "apt-get.*install" install.sh 2>/dev/null && pass "apt-get install present" || fail "apt-get install missing"

# Test 6: install.sh installs a systemd service
echo "=== Test: install.sh systemd service ==="
# install.sh delegates to tpi_write_systemd_unit in lib/common.sh
if grep -q "tpi_write_systemd_unit" install.sh 2>/dev/null && \
   grep -qE "Service\]|ExecStart=" lib/common.sh 2>/dev/null; then
    pass "systemd service generation present (via lib/common.sh)"
else
    fail "systemd service generation missing"
fi

# Test 7: install.sh has systemctl enable
echo "=== Test: install.sh systemctl enable ==="
grep -q "systemctl.*enable" install.sh 2>/dev/null && pass "systemctl enable present" || fail "systemctl enable missing"

# Test 8: install.sh has bootstrap URL
echo "=== Test: install.sh bootstrap URL ==="
grep -q "triangles-bootstrap\|bootstrap\.cryptographic-triangles" install.sh 2>/dev/null && pass "Bootstrap URL present" || fail "Bootstrap URL missing"

# Test 9: bootstrap.sh has download
echo "=== Test: bootstrap.sh download ==="
grep -qE "curl|wget" bootstrap.sh 2>/dev/null && pass "Download command present" || fail "Download command missing"

# Test 10: bootstrap.sh has tar extract
echo "=== Test: bootstrap.sh tar extract ==="
grep -q "tar.*xz\|tar.*gz" bootstrap.sh 2>/dev/null && pass "Tar extraction present" || fail "Tar extraction missing"

# Test 11: README has quick start
echo "=== Test: README quick start ==="
grep -qE "curl.*bootstrap|wget.*bootstrap" README.md 2>/dev/null && pass "README has bootstrap commands" || fail "README missing bootstrap commands"

# Test 12: BOOTSTRAP.md exists and has content
echo "=== Test: BOOTSTRAP.md ==="
if [ -f BOOTSTRAP.md ] && [ "$(wc -c < BOOTSTRAP.md)" -gt 500 ]; then
    pass "BOOTSTRAP.md exists with content"
else
    fail "BOOTSTRAP.md missing or empty"
fi

# Test 13: install.sh checks for root
echo "=== Test: root check ==="
grep -qE "root|id.*-u.*0" install.sh 2>/dev/null && pass "Root check present" || fail "Root check missing"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
