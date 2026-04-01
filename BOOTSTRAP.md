## TRI-PI Blockchain Bootstrap

Fast-sync your Raspberry Pi node with pre-synced blockchain data.

### Why Use Bootstrap?

**Without bootstrap:**
- Sync from genesis block (block 0)
- Takes days/weeks on Raspberry Pi
- Heavy CPU/disk usage during sync
- Network bandwidth intensive

**With bootstrap:**
- Start from latest block height
- Ready to mine in minutes
- Minimal resource usage
- Download current blockchain snapshot

### Installation

The TRI-PI installer offers automatic blockchain bootstrap during setup:

```bash
curl -sSL https://raw.githubusercontent.com/SamiAhmed7777/tri-pi/main/bootstrap.sh | bash
```

When prompted, choose **option 1** to download the pre-synced blockchain.

### What Gets Downloaded

The bootstrap package includes:
- `blk*.dat` - Blockchain data files
- `database/` - Block index
- `txleveldb/` - Transaction index
- `smsgDB/` - Secure messaging database
- `peers.dat` - Known peer cache
- `smsg.ini` - Messaging config

**Not included (for security):**
- `wallet.dat` - Your wallet is created fresh on first run
- `debug.log` - Generated during operation
- `onion/` - Hidden service keys generated automatically
- `tor_data/` - Tor state regenerated on startup

### After Installation

Start your node:
```bash
trianglesd
```

Check synchronization status:
```bash
trianglesd getinfo
```

The blockchain will continue syncing from the bootstrap snapshot's block height to the current network tip.

### First Run

On first startup, trianglesd will:
1. Load the bootstrap blockchain data
2. Generate a fresh wallet.dat
3. Create Tor hidden service keys
4. Begin syncing remaining blocks
5. Connect to the network via onion seeds

**Tip:** Watch sync progress with:
```bash
watch -n5 'trianglesd getinfo | grep blocks'
```

### Security Notes

1. **Fresh wallet** - Always generated locally, never downloaded
2. **Verify source** - Only use bootstrap from trusted URLs
3. **Network sync** - Remaining blocks verified via network consensus
4. **Regular updates** - Bootstrap snapshot updated weekly

### Troubleshooting

**If bootstrap download fails:**
- Installer automatically falls back to full sync from genesis
- You can manually download and extract:
  ```bash
  cd ~/.triangles
  curl -O http://194.233.88.206:8085/triangles-bootstrap.tar.gz
  tar xzf triangles-bootstrap.tar.gz
  ```

**Snapshot too old?**
- No problem! Your node will sync the remaining blocks automatically
- This is still much faster than syncing from block 0
