# TRI-PI GitHub Actions

## Automated Build Pipeline

This repository uses GitHub Actions to automatically rebuild TRI-PI whenever a new version of triangles_v5 is released.

### Workflows

#### `build-arm64.yml` - Automatic ARM64 Builder

**Triggers:**
1. **Manual dispatch** - Run builds on demand via GitHub UI
2. **Scheduled checks** - Every 6 hours, checks for new triangles_v5 releases
3. **Auto-build** - When a new version is detected, builds automatically

**What it does:**
1. Checks for new triangles_v5 releases
2. Builds trianglesd from source in ARM64 Docker container
3. Creates release package (tar.gz)
4. Updates VERSION file and documentation
5. Commits and pushes to main branch
6. Creates GitHub Release with binaries

**Build environment:**
- Ubuntu 24.04 ARM64 (via QEMU emulation)
- BerkeleyDB 4.8 (built from source)
- Boost 1.83, OpenSSL 3.0
- Full Tor integration

### Manual Trigger

To manually build a specific version:

1. Go to **Actions** tab
2. Select **Build TRI-PI ARM64** workflow
3. Click **Run workflow**
4. Enter version tag (e.g., `v5.4.5`)
5. Click **Run workflow**

### Automatic Updates

The workflow runs every 6 hours to check for new releases. When detected:
- Builds automatically
- Creates release
- Updates repo

No manual intervention needed!

### Version Tracking

Current version stored in `VERSION` file at repo root.
