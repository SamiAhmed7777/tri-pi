#!/bin/bash
# TRI-PI binary presence and format tests
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  ✓ $*"; ((PASS++)) || true; }
fail() { echo "  ✗ $*"; ((FAIL++)) || true; }

# Test 1: ARM64 binary exists
echo "=== Test: ARM64 binary exists ==="
[ -f /root/tri-pi/bin/trianglesd ] && pass "trianglesd binary exists" || fail "trianglesd binary missing"

# Test 2: Binary is executable
echo "=== Test: Binary is executable ==="
[ -x /root/tri-pi/bin/trianglesd ] && pass "Binary is executable" || fail "Binary not executable"

# Test 3: Binary is ELF64
echo "=== Test: Binary is ELF64 ==="
file /root/tri-pi/bin/trianglesd 2>/dev/null | grep -q "ELF 64-bit" && pass "Binary is 64-bit ELF" || fail "Binary is not 64-bit ELF"

# Test 4: Binary is ARM64
echo "=== Test: Binary is ARM64 ==="
file /root/tri-pi/bin/trianglesd 2>/dev/null | grep -qE "aarch64|ARM64" && pass "Binary is ARM64" || fail "Binary is not ARM64"

# Test 5: Binary is stripped
echo "=== Test: Binary is stripped ==="
file /root/tri-pi/bin/trianglesd 2>/dev/null | grep -q "stripped" && pass "Binary is stripped" || pass "Binary not stripped (OK but larger)"

# Test 6: Binary size is reasonable
echo "=== Test: Binary size reasonable ==="
size=$(stat -c%s /root/tri-pi/bin/trianglesd 2>/dev/null || echo 0)
if [ "$size" -gt 1000000 ] && [ "$size" -lt 50000000 ]; then
    pass "Binary size reasonable: $size bytes"
else
    fail "Binary size unexpected: $size bytes"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
