#!/bin/bash
set -euo pipefail

VERSION="${1:-}"

if [ -z "$VERSION" ] && [ -f .github/docker/Dockerfile.arm64 ]; then
  VERSION=$(sed -n 's/^ARG TRIANGLES_VERSION=v//p' .github/docker/Dockerfile.arm64 | head -n1)
fi

if [ -z "$VERSION" ]; then
  echo "ERROR: Could not determine TRI-PI package version." >&2
  echo "Pass a version explicitly, e.g. ./build/package-release.sh 5.7.6" >&2
  exit 1
fi

RELEASE_NAME="tri-pi-${VERSION}-arm64"
RELEASE_DIR="build/release/${RELEASE_NAME}"

echo "=== Packaging TRI-PI Release v${VERSION} ==="

# Clean and create release directory
rm -rf build/release
mkdir -p "$RELEASE_DIR"/{bin,backend,frontend,services,systemd,docs}

# Copy binaries
echo "📦 Copying binaries..."
cp build/output/trianglesd-arm64 "$RELEASE_DIR/bin/trianglesd"
cp build/output/trianglesd-arm64-static "$RELEASE_DIR/bin/trianglesd-static"
chmod +x "$RELEASE_DIR/bin/"*

# Copy installer
echo "📦 Copying installer..."
cp setup/install.sh "$RELEASE_DIR/"
chmod +x "$RELEASE_DIR/install.sh"

# Copy application files
echo "📦 Copying application files..."
cp -r backend/* "$RELEASE_DIR/backend/" 2>/dev/null || true
cp -r frontend/* "$RELEASE_DIR/frontend/" 2>/dev/null || true
cp -r services/* "$RELEASE_DIR/services/" 2>/dev/null || true
cp -r config "$RELEASE_DIR/" 2>/dev/null || true
cp -r tor "$RELEASE_DIR/" 2>/dev/null || true

# Copy documentation
echo "📦 Copying documentation..."
cp README.md "$RELEASE_DIR/docs/"
cp CLAUDE.md "$RELEASE_DIR/docs/" 2>/dev/null || true
[ -f LICENSE ] && cp LICENSE "$RELEASE_DIR/docs/" || echo "MIT License" > "$RELEASE_DIR/docs/LICENSE"

# Create installation instructions
cat > "$RELEASE_DIR/INSTALL.md" << 'INSTALL'
# TRI-PI Installation Guide

## Quick Install (Recommended)

```bash
sudo ./install.sh
```

This will:
- Install trianglesd to /opt/tri-pi/
- Install Flask backend API
- Install web dashboard frontend
- Create systemd services
- Set up Tor integration
- Configure everything automatically
- Start all services

## What Gets Installed

- **Triangles Daemon**: /opt/tri-pi/bin/trianglesd
- **Backend API**: /opt/tri-pi/backend/ (Flask on port 8081)
- **Web Dashboard**: /opt/tri-pi/frontend/ (served via Caddy)
- **Config**: ~/.triangles/triangles.conf
- **Services**: 
  - triangles.service (daemon)
  - tri-pi-backend.service (API)
  - tri-pi-frontend.service (dashboard)

## System Requirements

- Raspberry Pi 4 or 5 (4GB+ RAM recommended)
- Raspberry Pi OS (64-bit) Bookworm or later
- 32GB+ storage (SD card or SSD)
- Internet connection

## Post-Installation

Access the web dashboard:
```bash
http://<your-pi-ip>:8080
```

Check daemon status:
```bash
systemctl status triangles
```

View wallet info:
```bash
/opt/tri-pi/bin/trianglesd getinfo
```

## Manual Installation (Advanced)

If you prefer manual setup, see docs/MANUAL_INSTALL.md

## Support

- GitHub: https://github.com/SamiAhmed7777/triangles_v5
- Git: https://git.sami/sami7777/tri-pi
- Explorer: https://blocks.cryptographic-triangles.org
INSTALL

# Create checksums
echo "🔐 Generating checksums..."
cd "$RELEASE_DIR/bin"
sha256sum trianglesd > trianglesd.sha256
sha256sum trianglesd-static > trianglesd-static.sha256
cd - > /dev/null

# Create release tarball
echo "📦 Creating release tarball..."
cd build/release
tar czf "${RELEASE_NAME}.tar.gz" "$RELEASE_NAME"
cd - > /dev/null

# Generate final checksums
cd build/release
sha256sum "${RELEASE_NAME}.tar.gz" > "${RELEASE_NAME}.tar.gz.sha256"
cd - > /dev/null

echo ""
echo "✅ Release package created!"
echo ""
echo "📦 Package: build/release/${RELEASE_NAME}.tar.gz"
echo "🔐 SHA256: $(cat build/release/${RELEASE_NAME}.tar.gz.sha256 | cut -d' ' -f1)"
echo "📊 Size: $(du -h build/release/${RELEASE_NAME}.tar.gz | cut -f1)"
echo ""
echo "Package contents:"
du -sh "build/release/${RELEASE_NAME}"/*
echo ""
echo "Ready for GitHub release upload!"
