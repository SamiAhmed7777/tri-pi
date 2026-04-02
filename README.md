# TRI-PI — Triangles Node for ARM64

[![Latest Release](https://img.shields.io/github/v/release/SamiAhmed7777/tri-pi?label=Latest%20Release)](https://github.com/SamiAhmed7777/tri-pi/releases/latest)
[![Build Status](https://img.shields.io/github/actions/workflow/status/SamiAhmed7777/tri-pi/build-arm64.yml?label=ARM64%20Build)](https://github.com/SamiAhmed7777/tri-pi/actions)
[![Platform](https://img.shields.io/badge/platform-ARM64-blue)](https://github.com/SamiAhmed7777/tri-pi)

Run a [Triangles (TRI)](https://github.com/SamiAhmed7777/triangles_v5) cryptocurrency node on Raspberry Pi 4/5 or any ARM64 server. Includes Tor integration, systemd service, and optional blockchain bootstrap.

## Quick Start

### One-liner install

```bash
curl -sSL https://raw.githubusercontent.com/SamiAhmed7777/tri-pi/main/bootstrap.sh | sudo bash
```

Downloads the latest release, installs dependencies, creates a systemd service, and offers blockchain bootstrap. Ready in ~60 seconds.

### Manual install

```bash
# Download latest release
wget https://github.com/SamiAhmed7777/tri-pi/releases/latest/download/tri-pi-v5.5.0-arm64.tar.gz
tar xzf tri-pi-v5.5.0-arm64.tar.gz

# Install
sudo ./install.sh
```

## What's Included

| File | Purpose |
|------|---------|
| `bin/trianglesd` | Native ARM64 binary (stripped, ~5MB) |
| `install.sh` | Interactive installer with bootstrap option |
| `bootstrap.sh` | One-liner installer (fetches latest release) |
| `BOOTSTRAP.md` | Blockchain bootstrap guide |
| `docs/BUILD.md` | Build-from-source instructions |

## After Installation

```bash
# Start the node
sudo systemctl start triangles

# Check status
trianglesd -datadir=/root/.triangles getinfo

# Watch sync progress
watch -n5 'trianglesd -datadir=/root/.triangles getinfo | grep blocks'

# View logs
journalctl -u triangles -f
tail -f /root/.triangles/debug.log

# View Tor onion address
cat /root/.triangles/onion/hostname
```

### Common commands

```bash
trianglesd -datadir=/root/.triangles getblockcount      # Current block height
trianglesd -datadir=/root/.triangles getpeerinfo         # Connected peers
trianglesd -datadir=/root/.triangles getstakinginfo      # Staking status
trianglesd -datadir=/root/.triangles getnewaddress       # New address
trianglesd -datadir=/root/.triangles getbalance           # Wallet balance
```

> **Tip:** Create an alias to save typing:
> ```bash
> echo 'alias tri="trianglesd -datadir=/root/.triangles"' >> ~/.bashrc && source ~/.bashrc
> tri getinfo
> ```

## System Requirements

| | Minimum | Recommended |
|---|---------|-------------|
| **Platform** | Raspberry Pi 4 (64-bit) | Raspberry Pi 5 or ARM64 VPS |
| **OS** | Ubuntu 24.04, Pi OS 64-bit | Ubuntu 24.04 LTS |
| **RAM** | 2 GB | 4 GB |
| **Storage** | 5 GB free | 10 GB free |
| **Network** | Internet (Tor supported) | Wired ethernet |

## Blockchain Bootstrap

Syncing from genesis takes days/weeks on a Pi. The installer offers a pre-synced blockchain download (~1.3 GB) that gets you running in minutes.

If bootstrap fails during install (server unreachable from your network), you can manually transfer:

```bash
# From a machine that can reach the bootstrap server:
curl -O http://194.233.88.206:8085/triangles-bootstrap.tar.gz
scp triangles-bootstrap.tar.gz pi@your-pi:/tmp/

# On the Pi:
sudo systemctl stop triangles
cd /root/.triangles
tar xzf /tmp/triangles-bootstrap.tar.gz
sudo systemctl start triangles
```

## Tor Integration

trianglesd manages Tor automatically:
- Starts Tor as a child process on port 19099
- Generates a `.onion` hidden service address
- Connects to onion seed nodes
- No manual Tor configuration needed

**Do NOT** set `onion=` or `tor=` in the config — the daemon handles everything.

## Automated Builds

New releases are built automatically via GitHub Actions when upstream triangles_v5 publishes a release. The CI uses QEMU ARM64 emulation on GitHub-hosted runners.

**Manual trigger:** [Actions](https://github.com/SamiAhmed7777/tri-pi/actions) → "Build TRI-PI ARM64" → "Run workflow"

## Network

| Port | Protocol | Purpose |
|------|----------|---------|
| 24112 | TCP | P2P network |
| 19199 | TCP | RPC (localhost only) |
| 19099 | TCP | Tor SOCKS (internal) |

## Building from Source

See [docs/BUILD.md](docs/BUILD.md) for complete build instructions.

## License

See LICENSE file in the [source repository](https://github.com/SamiAhmed7777/triangles_v5).

---

Built with ❤️ for the Raspberry Pi community
