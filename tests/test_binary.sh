#!/bin/bash
# TRI-PI binary presence and format tests — paths relative to repo root

set -uo pipefail

PASS=0
FAIL=0

pass() { echo "  ✓ $*"; ((PASS++)) || true; }
fail() { echo "  ✗ $*"; ((FAIL++)) || true; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Test 1: ARM64 binary exists
echo "=== Test: ARM64 binary exists ==="
[ -f bin/tri7d ] && pass "tri7d binary exists" || fail "trianglesd binary missing"

# Test 2: Binary is executable
echo "=== Test: Binary is executable ==="
[ -x bin/tri7d ] && pass "Binary is executable" || fail "Binary not executable"

# Test 3: Binary is ELF64
echo "=== Test: Binary is ELF64 ==="
file bin/tri7d 2>/dev/null | grep -q "ELF 64-bit" && pass "Binary is 64-bit ELF" || fail "Binary is not 64-bit ELF"

# Test 4: Binary is ARM64
echo "=== Test: Binary is ARM64 ==="
file bin/tri7d 2>/dev/null | grep -qE "aarch64|ARM64" && pass "Binary is ARM64" || fail "Binary is not ARM64"

# Test 5: Binary is stripped
echo "=== Test: Binary is stripped ==="
file bin/tri7d 2>/dev/null | grep -q "stripped" && pass "Binary is stripped" || pass "Binary not stripped (OK but larger)"

# Test 6: Binary size is reasonable
echo "=== Test: Binary size reasonable ==="
size=$(stat -c%s bin/tri7d 2>/dev/null || echo 0)
if [ "$size" -gt 1000000 ] && [ "$size" -lt 50000000 ]; then
    pass "Binary size reasonable: $size bytes"
else
    fail "Binary size unexpected: $size bytes"
fi

# Test 7: TRI7-era ports (no legacy ports outside legacy/)
echo "=== Test: TRI7-era ports in scripts ==="
# 24112 is a VALID tri7-era peer port (legacy nodes still listen there and are
# legitimate attach targets, e.g. onion seeds) — only flag it outside seed lines.
if grep -rnE '19199|19099|24112' install.sh upgrade.sh bootstrap.sh tri-pi-doctor.sh lib/common.sh 2>/dev/null | grep -v '\.onion:24112' | grep -q .; then
    fail "legacy port strings found in TRI7-era scripts"
    grep -rnE '19199|19099|24112' install.sh upgrade.sh bootstrap.sh tri-pi-doctor.sh lib/common.sh | grep -v '\.onion:24112' || true
else
    pass "no legacy ports (19199/19099) outside onion seed targets"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
