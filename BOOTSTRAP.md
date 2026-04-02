## Blockchain Bootstrap

Fast-sync your Triangles node with a pre-synced blockchain snapshot instead of syncing from genesis (which takes days/weeks on a Pi).

### During Installation

Both `install.sh` and `bootstrap.sh` offer automatic bootstrap download. Choose option 1 when prompted.

### Manual Bootstrap

If the automatic download failed (e.g., server unreachable from your network), transfer the snapshot manually:

```bash
# On a machine that can reach the bootstrap server:
curl -O http://194.233.88.206:8085/triangles-bootstrap.tar.gz

# Transfer to your Pi:
scp triangles-bootstrap.tar.gz pi@your-pi:/tmp/

# On the Pi:
sudo systemctl stop triangles
cd /root/.triangles
tar xzf /tmp/triangles-bootstrap.tar.gz
sudo systemctl start triangles
```

### What's in the Snapshot

**Included:**
- `blk*.dat` — Blockchain data
- `txleveldb/` — Transaction/block index
- `database/` — BerkeleyDB environment
- `peers.dat` — Known peer cache

**Not included (generated fresh):**
- `wallet.dat` — Created on first run
- `onion/` — Tor hidden service keys
- `tor_data/` — Tor state
- `debug.log` — Runtime log

### After Bootstrap

Your node will:
1. Load the snapshot blockchain
2. Fast-import and verify blocks
3. Sync remaining blocks from peers
4. Generate a fresh wallet and Tor identity

Watch progress:
```bash
tail -f /root/.triangles/debug.log    # See FastImport progress
trianglesd -datadir=/root/.triangles getinfo   # Check block height
```

### Snapshot Updates

The bootstrap server updates automatically every Sunday at 4:00 AM UTC. The snapshot is always within a week of current.

### Security

- Wallet is **never** included — always generated locally
- Blockchain data is verified against network consensus during import
- Use only the official bootstrap URL or transfer from a trusted source
