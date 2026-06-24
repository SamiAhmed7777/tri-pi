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
wget https://github.com/SamiAhmed7777/tri-pi/releases/latest/download/tri-pi-$(curl -fsSL https://api.github.com/repos/SamiAhmed7777/triangles_v5/releases/latest | jq -r .tag_name | sed 's/^v//')-arm64.tar.gz
tar xzf tri-pi-*.tar.gz

# Install
sudo ./install.sh
```

## What's Included

| File | Purpose |
|------|---------|
| `bin/trianglesd` | Native ARM64 binary (stripped, ~5MB) |
| `install.sh` | Interactive installer with bootstrap option |
| `bootstrap.sh` | One-liner installer (fetches latest release) |
| `upgrade.sh` | In-place upgrade of an existing install — preserves config, wallet, blockchain, and Tor state |
| `tri-pi-doctor.sh` | Diagnostic report — checks binary version, service state, port bindings, Tor state, recent errors |
| `lib/common.sh` | Shared library (paths, pre-flights, systemd unit generation) sourced by all scripts |
| `BOOTSTRAP.md` | Blockchain bootstrap guide |
| `docs/BUILD.md` | Build-from-source instructions |
| `tests/` | Non-destructive test suite (55 tests across 4 scripts) |

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
curl -O https://bootstrap.cryptographic-triangles.org/tri-bootstrap.tar.gz
scp tri-bootstrap.tar.gz pi@your-pi:/tmp/

# On the Pi:
sudo systemctl stop triangles
cd /root/.triangles
tar xzf /tmp/tri-bootstrap.tar.gz
sudo systemctl start triangles
```

## Upgrading an Existing Install

To upgrade an existing TRI-PI install to a new upstream release without losing your config, wallet, or Tor hidden service:

```bash
# From the tri-pi release tarball:
sudo ./upgrade.sh

# Or from a specific version:
sudo ./upgrade.sh --to v5.9.25

# Or from a local tarball (useful for air-gapped upgrades):
sudo ./upgrade.sh --tarball /tmp/tri-pi-v5.9.25-arm64.tar.gz

# Just check what's available without making changes:
sudo ./upgrade.sh --check
```

The upgrade flow:

1. Stops the triangles service
2. Pre-flight checks: disk space, P2P port, stale Tor state
3. Downloads (or uses local) tarball, verifies SHA256
4. Backs up the current binary as `trianglesd.bak-<version>` (kept for rollback)
5. Atomic-swaps the new binary
6. Restarts the service and verifies version + height

**What is preserved (do not regress):**

- `triangles.conf` — your RPC creds, seed nodes, dbcache tuning
- `wallet.dat` — funds, keypool, transaction history
- `blk0001.dat`, `txleveldb/`, `database/` — synced blockchain (re-syncing takes days)
- `tor_data/` — Tor hidden service key (losing this = new `.onion` address, peers re-learn you)
- `/var/log/tri-pi/` — all historical logs

**Rollback** if a new version breaks your node (within 30 days):

```bash
sudo systemctl stop triangles
sudo cp /usr/local/bin/trianglesd.bak-v5.9.23 /usr/local/bin/trianglesd
sudo systemctl start triangles
```

## Diagnostics — `tri-pi-doctor.sh`

When something is wrong, run the doctor for a structured report:

```bash
sudo ./tri-pi-doctor.sh           # human-readable
sudo ./tri-pi-doctor.sh --json    # machine-readable for monitoring
```

The doctor checks 14 things including the two failure modes that catch most operators:

- **P2P port 24112 held by another process** — almost always stale Tor from a prior failed start. The doctor tells you the exact `kill -9` command.
- **Stale `tor_data/state` directory** — Tor fails to start with "State file is not a file". The doctor tells you the exact `rm -rf` + `systemctl restart` command.

Exit codes:

| Code | Meaning |
|------|---------|
| 0 | Healthy |
| 1 | Warnings (degraded but functional) |
| 2 | Failures (likely not functional) |
| 3 | Cannot run (not ARM64 / not root) |

## Common Failure Modes

These are the issues that actually come up in the field. The doctor detects all of them automatically.

### "Triangles: Tor failed to start. Triangles requires Tor to operate."

The Tor DataDirectory at `/root/.triangles/tor_data/state` is a non-empty directory instead of a file. Trianglesd can't auto-recover from this. Fix:

```bash
sudo rm -rf /root/.triangles/tor_data/state
sudo systemctl restart triangles
```

### "Unable to bind to 0.0.0.0:24112 — Triangles is probably already running"

A stale Tor or trianglesd process is holding the P2P port. The restart loop killed the daemon but not the child. Fix:

```bash
sudo ss -tlnp | grep 24112    # see who's holding it
sudo kill -9 <pid>            # kill the stale process
sudo systemctl restart triangles
```

### Daemon restarts repeatedly, eventually gives up with "Max restart retries"

The entrypoint's restart loop killed trianglesd but didn't clean up child processes. After 10 failed restarts (5–10 minutes), the service stops trying. Diagnose with `tri-pi-doctor.sh` to find the specific failure.

## Tor Integration

trianglesd manages Tor automatically:
- Starts Tor as a child process on port 19099
- Generates a `.onion` hidden service address
- Connects to onion seed nodes
- No manual Tor configuration needed

**Do NOT** set `onion=` or `tor=` in the config — the daemon handles everything.

## Automated Builds

New releases are built automatically via GitHub Actions when upstream `triangles_v5` publishes a release. The CI uses QEMU ARM64 emulation on GitHub-hosted runners.

**Manual trigger:** [Actions](https://github.com/SamiAhmed7777/tri-pi/actions) → "Build TRI-PI ARM64" → "Run workflow". You can leave the version blank to build the latest upstream release, or provide a specific upstream tag such as `v5.8.1`.

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
