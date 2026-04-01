# TRI-PI v5.4.4 - ARM64 Edition

Complete Triangles (TRI) cryptocurrency node package for Raspberry Pi 4/5 (64-bit) and ARM64 servers.

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

## Quick Installation

```bash
# Extract the package
tar xzf tri-pi-v5.4.4-arm64.tar.gz
cd tri-pi-v5.4.4-arm64

# Run installer (requires sudo)
sudo ./install.sh
```

## Usage

### Start the node
```bash
trianglesd
```

### Check node status
```bash
trianglesd getinfo
```

### Get help
```bash
trianglesd help
```

### Common commands
```bash
trianglesd getblockcount        # Current block height
trianglesd getpeerinfo          # Connected peers
trianglesd getstakinginfo       # Staking status
trianglesd getnewaddress        # Generate new address
trianglesd getbalance           # Wallet balance
```

## Tor Integration

trianglesd v5.4.4 includes built-in Tor management:

- **Automatic Tor startup** - No manual configuration needed
- **Hidden service generation** - Creates .onion address automatically
- **SOCKS proxy** - Built-in at port 19099
- **Peer connectivity** - Connects to onion seed nodes

**To disable Tor:**
```bash
trianglesd -notor
```

**Check your onion address:**
```bash
trianglesd getinfo | grep onion
```

## Configuration

Configuration file: `~/.triangles/triangles.conf`

The installer creates a default config. You can edit it for custom settings:

```bash
nano ~/.triangles/triangles.conf
```

### Important config options:

```
server=1               # Enable RPC server
daemon=1               # Run as daemon
listen=1               # Accept incoming connections
txindex=1              # Full transaction index
maxconnections=125     # Max peer connections
rpcport=24113          # RPC port
```

## Building from Source

### Prerequisites

```bash
# Install build dependencies
sudo apt-get update
sudo apt-get install -y git build-essential libtool autotools-dev automake \
    pkg-config libssl-dev libevent-dev bsdmainutils libboost-all-dev \
    libminiupnpc-dev libzmq3-dev tor curl wget
```

### Build BerkeleyDB 4.8

```bash
# Download and extract
wget http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz
tar xzf db-4.8.30.NC.tar.gz
cd db-4.8.30.NC/build_unix

# Update config scripts for ARM64
wget -O ../dist/config.guess \
  'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'
wget -O ../dist/config.sub \
  'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD'
chmod +x ../dist/config.guess ../dist/config.sub

# Configure and build
../dist/configure --enable-cxx --disable-shared --with-pic --prefix=/usr/local
make -j$(nproc)
sudo make install
sudo ldconfig
```

### Build trianglesd

```bash
# Clone source
git clone https://github.com/SamiAhmed7777/triangles_v5.git
cd triangles_v5
git checkout v5.4.4

# Build daemon
cd src
make -f makefile.unix -j$(nproc) USE_UPNP=1

# Install
sudo strip trianglesd
sudo cp trianglesd /usr/local/bin/
sudo chmod +x /usr/local/bin/trianglesd
```

### Verify build

```bash
trianglesd --version
# Output: Triangles version v5.4.4
```

## Seed Nodes (v5.4.4)

The following onion seed nodes are hardcoded in v5.4.4:

1. `gxvrhv3qitnc6kobrhsrse46bmcfitnybapor3or3oczzuxn6hfzxyid.onion` (DNS2)
2. `i6tk7soznftvoibtskwlezviskiererhjndpsmrff4kaxw7jnd5izfqd.onion` (DNS3)
3. `futmtrvh6j34t7s6yjdxfia6iwuyfzwh4k5eqfof5kfhoqk3xmi3qoqd.onion` (Original)
4. `uddaxjbo3lh2zskg7w6gwln4ty5cel7q4c5jbx7fdtv6zf2j47gdlyad.onion` (Seed-1)
5. `el5sirhhleecuctpeeprelzubpqmoqivvra3rzlwbjttinxa4fq3wnid.onion` (Seed-2)
6. `sj5dhybnlp3v4y5niyc5unrnd6s43lyx5ibup7rolyosjbi2u2hsbvyd.onion` (Seed-3)
7. `i3kr5meha7se4ns3wss3h7v46m6uksfzv4wrohdqxpj6n35wyo2bvlid.onion` (Seed-4)

## Network Information

- **Mainnet Port:** 17771
- **RPC Port:** 24113 (configurable)
- **Tor SOCKS Port:** 19099 (internal)
- **Protocol Version:** 70206
- **Consensus:** Hybrid PoW/PoS

## Troubleshooting

### Tor connection issues

If Tor fails to start:
```bash
# Check Tor status
sudo systemctl status tor

# Restart Tor
sudo systemctl restart tor

# Check logs
trianglesd getinfo 2>&1 | grep -i tor
```

### Sync issues

If blockchain won't sync:
```bash
# Check connections
trianglesd getpeerinfo

# Add seed nodes manually
trianglesd addnode "uddaxjbo3lh2zskg7w6gwln4ty5cel7q4c5jbx7fdtv6zf2j47gdlyad.onion" "onetry"
```

### Port conflicts

If port 24112 is already in use:
```bash
# Check what's using the port
sudo lsof -i :24112

# Edit config to use different port
nano ~/.triangles/triangles.conf
# Change: port=24113
```

## Support

- **GitHub:** https://github.com/SamiAhmed7777/triangles_v5
- **Issues:** https://github.com/SamiAhmed7777/triangles_v5/issues

## License

See LICENSE file in the source repository.

---

Built with ❤️ for the Raspberry Pi and ARM64 community
