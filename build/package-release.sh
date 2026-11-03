#!/bin/bash
# TRI-PI release packager — TRI7 era (tri7d).
# Packages bin/tri7d + bin/tri7-balances (aarch64 tri7 client binaries) with
# the TRI7-era installer/lib/doctor into a release tarball.
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ] && [ -f VERSION ]; then
  VERSION="$(cat VERSION | tr -d '[:space:]')"
fi
if [ -z "$VERSION" ]; then
  echo "ERROR: pass a version, e.g. ./build/package-release.sh v0.1.0-tri7.1" >&2
  exit 1
fi

RELEASE_NAME="tri-pi-${VERSION}-arm64"
RELEASE_DIR="build/release/${RELEASE_NAME}"

echo "=== Packaging TRI-PI Release ${VERSION} (tri7d) ==="

rm -rf build/release
mkdir -p "$RELEASE_DIR"/{bin,docs}

echo "📦 Copying tri7d binaries..."
[ -f bin/tri7d ]          || { echo "ERROR: bin/tri7d missing — build it first (see .github/workflows/build-arm64.yml or docs in README)" >&2; exit 1; }
[ -f bin/tri7-balances ]  || { echo "ERROR: bin/tri7-balances missing" >&2; exit 1; }
cp bin/tri7d bin/tri7-balances "$RELEASE_DIR/bin/"
chmod +x "$RELEASE_DIR/bin/"*

echo "📦 Copying installer + library..."
cp install.sh upgrade.sh tri-pi-doctor.sh "$RELEASE_DIR/"
mkdir -p "$RELEASE_DIR/lib"
cp lib/common.sh "$RELEASE_DIR/lib/"
chmod +x "$RELEASE_DIR/"*.sh

echo "📦 Copying documentation..."
cp README.md BOOTSTRAP.md VERSION "$RELEASE_DIR/docs/" 2>/dev/null || true
[ -f LICENSE ] && cp LICENSE "$RELEASE_DIR/docs/" || echo "MIT License" > "$RELEASE_DIR/docs/LICENSE"

cat > "$RELEASE_DIR/INSTALL.md" << 'INSTALL'
# TRI-PI Installation Guide (tri7d)

## Quick Install

sudo ./install.sh

What gets installed:
- tri7d binary -> /usr/local/bin/tri7d  (also tri7-balances)
- Config       -> <data>/triangles.conf (rpcuser/rpcpassword; ports via systemd wrapper)
- systemd      -> triangles.service: tri7d --forever, RPC 19112, P2P 24113,
                  tor SOCKS 9050 (the Pi's tor service), onion seeds via --onion

Status: tri7d --status --state-dir <data>   (JSON: height, peers, staleness)
Sync:   fresh sync via P2P gap-fill (default) or TRI_PI_BOOTSTRAP_URL archive.

NOTE: tri7d is a node daemon. Staking/wallet operations need a wallet and the
RPC surface — see the tri7 repo (github.com/SamiAhmed7777/tri7).
INSTALL

echo "🔐 Generating checksums..."
(cd "$RELEASE_DIR/bin" && sha256sum tri7d tri7-balances > SHA256SUMS)

echo "📦 Creating release tarball..."
(cd build/release && tar czf "${RELEASE_NAME}.tar.gz" "$RELEASE_NAME")
(cd build/release && sha256sum "${RELEASE_NAME}.tar.gz" > "${RELEASE_NAME}.tar.gz.sha256")

echo ""
echo "📦 Package: build/release/${RELEASE_NAME}.tar.gz"
echo "🔐 SHA256: $(cut -d' ' -f1 "build/release/${RELEASE_NAME}.tar.gz.sha256")"
echo "📊 Size: $(du -h "build/release/${RELEASE_NAME}.tar.gz" | cut -f1)"
echo "Ready for GitHub release upload!"
