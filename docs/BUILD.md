# Building trianglesd v5.4.4 from Source (ARM64)

Complete step-by-step build instructions for ARM64 platforms (Raspberry Pi 4/5, ARM servers).

## Build Environment

**Tested on:**
- Ubuntu 24.04 ARM64
- Hetzner Cloud CAX11 (ARM64)
- Raspberry Pi OS 64-bit

**Build time:** ~15-20 minutes (varies by CPU)

## Step 1: Install Dependencies

```bash
sudo apt-get update
sudo apt-get install -y \
    git build-essential libtool autotools-dev automake pkg-config \
    libssl-dev libevent-dev bsdmainutils libboost-all-dev \
    libminiupnpc-dev libzmq3-dev tor curl wget
```

**Packages explained:**
- `build-essential` - GCC, G++, make
- `libboost-all-dev` - Boost libraries (1.83.0 on Ubuntu 24.04)
- `libssl-dev` - OpenSSL (for crypto functions)
- `libevent-dev` - Event notification library
- `libminiupnpc-dev` - UPnP support
- `libzmq3-dev` - ZeroMQ (messaging)
- `tor` - Tor network connectivity

## Step 2: Build BerkeleyDB 4.8

trianglesd requires BerkeleyDB 4.8 for wallet compatibility.

```bash
# Create build directory
mkdir -p ~/build-deps && cd ~/build-deps

# Download BerkeleyDB 4.8
wget http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz
tar xzf db-4.8.30.NC.tar.gz
cd db-4.8.30.NC/build_unix
```

### Update config scripts for ARM64

The original BerkeleyDB 4.8 config scripts are too old for ARM64. Update them:

```bash
wget -O ../dist/config.guess \
  'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'

wget -O ../dist/config.sub \
  'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD'

chmod +x ../dist/config.guess ../dist/config.sub
```

### Configure and build

```bash
# Configure for ARM64
../dist/configure \
    --enable-cxx \
    --disable-shared \
    --with-pic \
    --prefix=/usr/local

# Build (use all CPU cores)
make -j$(nproc)

# Install
sudo make install
sudo ldconfig
```

**Verify installation:**
```bash
ls -l /usr/local/lib/libdb*
# Should show libdb-4.8.a, libdb.a, libdb_cxx-4.8.a, libdb_cxx.a
```

## Step 3: Clone triangles_v5

```bash
cd ~
git clone https://github.com/SamiAhmed7777/triangles_v5.git
cd triangles_v5
git checkout v5.4.4
```

## Step 4: Build trianglesd

```bash
cd src
make -f makefile.unix -j$(nproc) USE_UPNP=1
```

**Build flags:**
- `-j$(nproc)` - Parallel compilation (uses all CPU cores)
- `USE_UPNP=1` - Enable UPnP port mapping

**Build output:** `trianglesd` binary (~85MB before stripping)

### Common build warnings (safe to ignore)

- OpenSSL deprecation warnings (SHA256, RIPEMD160)
- Boost deprecated copy warnings
- Format string warnings

These are cosmetic and don't affect functionality.

## Step 5: Install the Binary

```bash
# Strip debug symbols (reduces size to ~40MB)
strip trianglesd

# Compress with UPX (RECOMMENDED - reduces to ~1.6MB!)
sudo apt-get install -y upx-ucl
upx --best --lzma trianglesd
# Before: ~40MB → After: ~1.6MB (80% reduction)

# Install to system
sudo cp trianglesd /usr/local/bin/
sudo chmod +x /usr/local/bin/trianglesd
```

**UPX Compression Benefits:**
- 80% smaller binary (40MB → 1.6MB)
- Faster download/transfer
- No performance penalty (decompresses to RAM on load)
- Fully reversible: `upx -d trianglesd`

**Verify installation:**
```bash
trianglesd --version
# Output: Triangles version v5.4.4

trianglesd --help | head -20
# Should show usage information
```

## Step 6: Create Configuration

```bash
# Create data directory
mkdir -p ~/.triangles

# Generate random RPC password
RPC_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)

# Create config file
cat > ~/.triangles/triangles.conf << CONFIG
server=1
daemon=1
listen=1
txindex=1

# Tor integration (managed automatically by trianglesd)
# Seed nodes (v5.4.4)
addnode=gxvrhv3qitnc6kobrhsrse46bmcfitnybapor3or3oczzuxn6hfzxyid.onion
addnode=i6tk7soznftvoibtskwlezviskiererhjndpsmrff4kaxw7jnd5izfqd.onion
addnode=uddaxjbo3lh2zskg7w6gwln4ty5cel7q4c5jbx7fdtv6zf2j47gdlyad.onion
addnode=el5sirhhleecuctpeeprelzubpqmoqivvra3rzlwbjttinxa4fq3wnid.onion
addnode=sj5dhybnlp3v4y5niyc5unrnd6s43lyx5ibup7rolyosjbi2u2hsbvyd.onion
addnode=i3kr5meha7se4ns3wss3h7v46m6uksfzv4wrohdqxpj6n35wyo2bvlid.onion

# RPC
rpcuser=tripi
rpcpassword=$RPC_PASS
rpcallowip=127.0.0.1
rpcport=24113

maxconnections=125
CONFIG

chmod 600 ~/.triangles/triangles.conf
```

## Step 7: Enable Tor

```bash
sudo systemctl enable tor
sudo systemctl start tor
sudo systemctl status tor
```

## Step 8: Start trianglesd

```bash
# Start daemon
trianglesd

# Check status (wait 10-15 seconds for startup)
trianglesd getinfo

# Monitor connections
trianglesd getpeerinfo
```

## Build Notes

### Tor Integration

trianglesd v5.4.4 includes:
- **Embedded Tor management** - Starts Tor automatically
- **SOCKS proxy** on port 19099 (internal)
- **Onion service generation** - Creates .onion address
- **Onion seed nodes** - Connects via Tor by default

**Important:** Do NOT set `onion=` or `tor=` in config. Let trianglesd manage it.

### Makefile Options

The `makefile.unix` supports several options:

```bash
# Basic build
make -f makefile.unix

# With UPnP
make -f makefile.unix USE_UPNP=1

# With IPv6
make -f makefile.unix USE_IPV6=1

# Debug build
make -f makefile.unix DEBUG=1

# Clean
make -f makefile.unix clean
```

### Cross-Compilation

To cross-compile for ARM64 from x86_64:

```bash
# Install cross-compiler
sudo apt-get install g++-aarch64-linux-gnu

# Modify makefile or use environment variables
CXX=aarch64-linux-gnu-g++ \
    make -f makefile.unix \
    USE_UPNP=1
```

## Troubleshooting

### BerkeleyDB not found

If compilation fails with "db_cxx.h not found":

```bash
# Check installation
ls -l /usr/local/include/db_cxx.h
ls -l /usr/local/lib/libdb_cxx.a

# Ensure ldconfig was run
sudo ldconfig
```

### Boost version mismatch

Ubuntu 24.04 uses Boost 1.83. Older systems may have issues. Ensure `libboost-all-dev` is installed.

### OpenSSL warnings

Deprecated API warnings are safe to ignore. trianglesd uses older OpenSSL APIs but they still work.

## Build Artifacts

After successful build:

- **Binary:** `src/trianglesd` (~85MB, ~40MB stripped)
- **LevelDB:** `src/leveldb/libleveldb.a`, `src/leveldb/libmemenv.a`
- **Object files:** `src/obj/*.o`

Clean with:
```bash
make -f makefile.unix clean
```

---

**Build time breakdown** (4-core ARM server):
- BerkeleyDB: ~5 minutes
- trianglesd: ~10 minutes
- **Total: ~15 minutes**
