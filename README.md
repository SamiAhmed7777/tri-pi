# TRI-PI — Triangles TRI7 Wallet Appliance for ARM64 (tri7d)

[![Latest Release](https://img.shields.io/github/v/release/SamiAhmed7777/tri-pi?label=Latest%20Release)](https://github.com/SamiAhmed7777/tri-pi/releases/latest)
[![Build Status](https://img.shields.io/github/actions/workflow/status/SamiAhmed7777/tri-pi/build-arm64.yml?label=ARM64%20Build)](https://github.com/SamiAhmed7777/tri-pi/actions)
[![Platform](https://img.shields.io/badge/platform-ARM64-blue)](https://github.com/SamiAhmed7777/tri-pi)

**TRI-PI is a fully functioning Triangles WALLET on a plug-in box** (2026-11-14):
the installer provisions the node AND creates a 24-word wallet, the daemon runs
with `--wallet` (balance, receive, send, staking-by-default), the `tri7` wallet
CLI manages keys, and `tri7-appliance` is the one-command manager
(status / backup / restore / upgrade). P2P is loopback-backed and firewalled —
**Triangles is never on public clearnet**; the tor onion network carries the
traffic.

Run a **tri7d** node — the modern Rust full-node client from
[tri7](https://github.com/SamiAhmed7777/tri7) — on Raspberry Pi 4/5 or any
ARM64 server. Includes Tor integration, systemd service, and optional
blockchain bootstrap.

> **TRI7 era (v7.0.3-tri7.2):** TRI-PI now ships **tri7d** (`follow_tip`), the
> pure-Rust client that replays the legacy chain byte-for-byte — plus the
> wallet appliance layer (wallet CLI, `--wallet` daemon, appliance manager,
> no-clearnet firewall policy). The legacy C++ `trianglesd` is retired; its
> ARM64 binary is kept under `legacy/` for rollback only.

## Wallet appliance quick start

```bash
sudo ./install.sh        # node + 24-word wallet + staking + firewall, one command
tri7-appliance status    # balance, staking, last reward, peers, wallet
tri7-appliance backup    # wallet + chain snapshot (KEEP PRIVATE)
```

The 24 words printed at install are the ONLY backup — write them on paper.

## TRI7-era facts

| Item | Value |
|------|-------|
| Daemon binary | `tri7d` (= tri7's `follow_tip --forever`), plus `tri7-balances` |
| JSON-RPC | **19112** (native surface; loopback-only bind inside tri7d) |
| Inbound P2P | **24113** (listener; also serves + relays blocks) |
| Tor | Pi's `tor` service, SOCKS **9050** — tri7d dials `.onion` seeds natively via `--socks` |
| Outbound seeds | `--daemon 100.85.236.10:24113` + `--onion <fleet seeds>` (see `lib/common.sh`, overridable via `TRI_PI_SEED_DIRECT` / `TRI_PI_SEED_ONIONS`) |
| Conf | `triangles.conf` — tri7d reads `rpcuser=` / `rpcpassword=`; ports come from the systemd wrapper flags |
| Sync | Fresh sync via **P2P gap-fill** (default). Optional tri7 `blk0001.dat` archive via `TRI_PI_BOOTSTRAP_URL` (+ `TRI_PI_BOOTSTRAP_SHA256`); the canonical archive lives on DNS2 at `/root/.triangles/blk0001.dat`. The legacy `triangles-bootstrap.tar.gz` URLs are dead AND incompatible with tri7d |
| Staking | tri7d is a node daemon; staking/wallet ops go through the RPC surface with a wallet (see the tri7 repo) |

## Quick Start

### One-liner install

```bash
curl -sSL https://raw.githubusercontent.com/SamiAhmed7777/tri-pi/main/bootstrap.sh | sudo bash
```

Downloads the latest release, installs dependencies, creates a systemd service, and starts the node. Ready in ~60 seconds.

### Manual install

```bash
wget https://github.com/SamiAhmed7777/tri-pi/releases/latest/download/tri-pi-*-arm64.tar.gz
tar xzf tri-pi-*.tar.gz

# Install
sudo ./install.sh
```

## What's Included

| File | Purpose |
|------|---------|
| `bin/tri7d` | tri7d — tri7 daemon (native ARM64, stripped, ~2.5MB) |
| `bin/tri7-balances` | tri7 replay/balances tool (native ARM64) |
| `legacy/` | LEGACY C++ `trianglesd` binary + rollback notes (not installed) |
| `install.sh` | Interactive installer with bootstrap option |
| `bootstrap.sh` | One-liner installer (fetches latest release) |
| `upgrade.sh` | In-place upgrade of an existing install — preserves config, wallet, blockchain, and Tor state |
| `tri-pi-doctor.sh` | Diagnostic report — checks binary version, service state, port bindings, Tor state, recent errors |
| `lib/common.sh` | Shared library (paths, pre-flights, systemd unit generation) sourced by all scripts |
| `BOOTSTRAP.md` | Blockchain bootstrap guide |
| `docs/BUILD.md` | Build-from-source instructions |
| `tests/` | Non-destructive test suite (`test_binary.sh` + installer/upgrade/doctor suites) |

## After Installation

```bash
# Start the node
sudo systemctl start triangles

# Check status
tri7d --status --state-dir /root/.triangles   # JSON: height, peers, staleness

# Watch sync progress
watch -n5 "tri7d --status --state-dir /root/.triangles | jq .height"

# View logs
journalctl -u triangles -f
tail -f /root/.triangles/debug.log

# View Tor onion address
cat /root/.triangles/onion/hostname
```

### Common commands

```bash
tri7d --status --state-dir /root/.triangles | jq .height   # Current block height
tri7d --status --state-dir /root/.triangles | jq .peers    # Connected peers
# staking/wallet ops: tri7 RPC surface on 19112 (see tri7 repo)
# (wallet RPCs require a wallet + RPC creds in triangles.conf)

```

> **Tip:** Create an alias to save typing:
> ```bash
> echo 'alias tri="tri7d --status --state-dir /root/.triangles"' >> ~/.bashrc && source ~/.bashrc
> tri | jq .height
> ```

## System Requirements

| | Minimum | Recommended |
|---|---------|-------------|
| **Platform** | Raspberry Pi 4 (64-bit) | Raspberry Pi 5 or ARM64 VPS |
| **OS** | Ubuntu 24.04, Pi OS 64-bit | Ubuntu 24.04 LTS |
| **RAM** | 2 GB | 4 GB |
| **Storage** | 5 GB free | 10 GB free |
| **Network** | Internet (Tor supported) | Wired ethernet |

## Blockchain Sync (TRI7 era)

tri7d **fresh-syncs via P2P gap-fill** — it backfills headers and blocks from
seed peers and verifies everything locally. On a Pi this takes hours, not the
days/weeks a from-genesis legacy sync took, and no snapshot download is needed.

If you host a tri7-era `blk0001.dat` block archive (the canonical one lives on
DNS2 at `/root/.triangles/blk0001.dat`), install.sh / bootstrap.sh can fetch it:

```bash
sudo TRI_PI_BOOTSTRAP_URL=http://your-server/blk0001.dat \
     TRI_PI_BOOTSTRAP_SHA256=<sha256> \
     ./install.sh
```

The legacy `triangles-bootstrap.tar.gz` leveldb tarballs are dead URLs AND
incompatible with tri7d — do not use them.

## Upgrading an Existing Install

To upgrade an existing TRI-PI install to a new upstream release without losing your config, wallet, or Tor hidden service:

```bash
# From the tri-pi release tarball:
sudo ./upgrade.sh

# Or from a specific version:
sudo ./upgrade.sh --to v7.0.0-tri7.1

# Or from a local tarball (useful for air-gapped upgrades):
sudo ./upgrade.sh --tarball /tmp/tri-pi-v7.0.0-tri7.1-arm64.tar.gz

# Just check what's available without making changes:
sudo ./upgrade.sh --check
```

The upgrade flow:

1. Stops the triangles service
2. Pre-flight checks: disk space, P2P port, stale Tor state
3. Downloads (or uses local) tarball, verifies SHA256
4. Backs up the current binary as `tri7d.bak-<version>` (kept for rollback)
5. Atomic-swaps the new tri7d binary
6. Restarts the service and verifies the daemon via `tri7d --status`

**What is preserved (do not regress):**

- `triangles.conf` — your RPC creds (rpcuser/rpcpassword; tri7d takes ports from the systemd wrapper)
- `wallet.dat` — funds, keypool, transaction history
- `blk0001.dat` — block archive + tri7d state (`tipstate.json`, `index/`)
- `tor_data/` — Tor hidden service key (losing this = new `.onion` address, peers re-learn you)
- `/var/log/tri-pi/` — all historical logs

**Rollback** if a new version breaks your node (within 30 days):

```bash
sudo systemctl stop triangles
sudo cp /usr/local/bin/tri7d.bak-v7.0.0-tri7.1 /usr/local/bin/tri7d
sudo systemctl start triangles
```

## Diagnostics — `tri-pi-doctor.sh`

When something is wrong, run the doctor for a structured report:

```bash
sudo ./tri-pi-doctor.sh           # human-readable
sudo ./tri-pi-doctor.sh --json    # machine-readable for monitoring
```

The doctor checks 14 things including the two failure modes that catch most operators:

- **P2P port 24113 held by another process** — almost always stale Tor from a prior failed start. The doctor tells you the exact `kill -9` command.
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

### "Tor failed to start"

The Tor DataDirectory at `/root/.triangles/tor_data/state` is a non-empty directory instead of a file (affects the Pi's tor service). Fix:

```bash
sudo rm -rf /root/.triangles/tor_data/state
sudo systemctl restart triangles
```

### "Unable to bind P2P port 24113 — probably already running"

A stale Tor or tri7d process is holding the P2P port. Fix:

```bash
sudo ss -tlnp | grep 24113    # see who's holding it
sudo kill -9 <pid>            # kill the stale process
sudo systemctl restart triangles
```

### Daemon restarts repeatedly

systemd restarts tri7d with `Restart=on-failure` / `RestartSec=30` — it keeps
retrying indefinitely. `systemctl stop triangles` keeps it stopped. Diagnose
with `tri-pi-doctor.sh` to find the specific failure.

## Tor Integration

tri7d does NOT manage Tor itself — the Pi's `tor` service provides the SOCKS
proxy on **9050**, and tri7d dials `.onion` seed peers through it (`--socks
127.0.0.1:9050`). Onion hidden-service operation (inbound .onion peering) can
be added with a torrc `HiddenServiceDir` pointing at the P2P port 24113. The
systemd unit orders itself `After=tor.service`.

## Automated Builds

New releases are built automatically via GitHub Actions: tri7d is compiled
**natively on an ARM64 GitHub runner** (`ubuntu-24.04-arm`) from the
[tri7](https://github.com/SamiAhmed7777/tri7) repo — no QEMU, no cross toolchain
(rustup + gcc only). Releases are dispatched when tri7 publishes a release.

**Manual trigger:** [Actions](https://github.com/SamiAhmed7777/tri-pi/actions) → "Build TRI-PI ARM64 (tri7d)" → "Run workflow". Leave the version blank to build tri7 master, or give a tri7 tag such as `v0.1.0`.

## Network

| Port | Protocol | Purpose |
|------|----------|---------|
| 24113 | TCP | P2P (inbound listener; tri7d serves + relays blocks) |
| 19112 | TCP | JSON-RPC (native tri7d surface; loopback-only bind in tri7d) |
| 9050  | TCP | Tor SOCKS (the Pi's tor service — outbound .onion peering) |

## Building from Source

See [docs/BUILD.md](docs/BUILD.md) for complete build instructions.

## License

See LICENSE file in the [source repository](https://github.com/SamiAhmed7777/tri7).

---

Built with ❤️ for the Raspberry Pi community
