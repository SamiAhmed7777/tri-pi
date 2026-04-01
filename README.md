# TRI-PI v5.4.4 - ARM64 Edition

[![Latest Release](https://img.shields.io/github/v/release/SamiAhmed7777/tri-pi?label=Latest%20Release)](https://github.com/SamiAhmed7777/tri-pi/releases/latest)
[![Build Status](https://img.shields.io/github/actions/workflow/status/SamiAhmed7777/tri-pi/build-arm64.yml?label=ARM64%20Build)](https://github.com/SamiAhmed7777/tri-pi/actions)
[![Platform](https://img.shields.io/badge/platform-ARM64-blue)](https://github.com/SamiAhmed7777/tri-pi)

Complete Triangles (TRI) cryptocurrency node package for Raspberry Pi 4/5 (64-bit) and ARM64 servers.

## Quick Start

### Download Latest Release

```bash
# Get latest version
wget https://github.com/SamiAhmed7777/tri-pi/releases/latest/download/tri-pi-v5.4.4-arm64.tar.gz
tar xzf tri-pi-v5.4.4-arm64.tar.gz
cd tri-pi-v5.4.4-arm64

# Install
sudo ./install.sh

# Start node
trianglesd
```

### Or Clone and Build from Source

```bash
git clone https://github.com/SamiAhmed7777/tri-pi.git
cd tri-pi
sudo ./install.sh
```

## What's Included

- **trianglesd** v5.4.4 - Native ARM64 binary (85MB)
- **Tor integration** - Built-in hidden service support
- **Updated seed nodes** - Latest v5.4.4 onion addresses
- **Auto-installer** - One-command setup
- **Full documentation** - Build instructions and usage guide

## System Requirements

- **Platform:** Raspberry Pi 4/5 (64-bit) or any ARM64 Linux server
- **OS:** Ubuntu 24.04 ARM64, Raspberry Pi OS 64-bit, or compatible
- **RAM:** 2GB minimum (4GB recommended)
- **Storage:** 10GB free space (blockchain grows over time)
- **Network:** Internet connection (Tor supported)

## Automated Builds

New releases are automatically built via GitHub Actions whenever upstream trianglesd is updated.

**Manual trigger:** Go to [Actions](https://github.com/SamiAhmed7777/tri-pi/actions) → "Build TRI-PI ARM64" → "Run workflow"

## Usage

### Start the node
```bash
trianglesd
```

### Check node status
```bash
trianglesd getinfo
```

### Common commands
```bash
trianglesd getblockcount        # Current block height
trianglesd getpeerinfo          # Connected peers
trianglesd getstakinginfo       # Staking status
trianglesd getnewaddress        # Generate new address
trianglesd getbalance           # Wallet balance
```

## Documentation

- **[Build Guide](docs/BUILD.md)** - Complete build instructions from source
- **[Installation](install.sh)** - Automated installer script
- **[Releases](https://github.com/SamiAhmed7777/tri-pi/releases)** - Download pre-built packages

## Tor Integration

trianglesd v5.4.4 includes built-in Tor management:

- **Automatic Tor startup** - No manual configuration needed
- **Hidden service generation** - Creates .onion address automatically
- **SOCKS proxy** - Built-in at port 19099
- **Peer connectivity** - Connects to onion seed nodes

**Check your onion address:**
```bash
trianglesd getinfo | grep onion
```

## Support

- **GitHub Issues:** [Report bugs or request features](https://github.com/SamiAhmed7777/tri-pi/issues)
- **Upstream:** [triangles_v5](https://github.com/SamiAhmed7777/triangles_v5)

## License

See LICENSE file in the source repository.

---

Built with ❤️ for the Raspberry Pi and ARM64 community
