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
- Only ~500MB download

### Creating a Blockchain Snapshot

Run on a fully-synced node (DNS2, DNS3, etc.):

```bash
# Download snapshot creator
curl -L -o create-snapshot.sh \
  https://raw.githubusercontent.com/SamiAhmed7777/tri-pi/main/scripts/create-blockchain-snapshot.sh

chmod +x create-snapshot.sh

# Create snapshot (stops daemon temporarily)
./create-snapshot.sh
```

**Output:**
- `tri-blockchain-v5.4.4-YYYY-MM-DD.tar.gz` - Compressed blockchain
- `snapshot-info.txt` - Metadata (block height, checksums)

### Hosting the Snapshot

**Option 1: GitHub Release** (recommended for public distribution)
```bash
gh release upload v5.4.4 tri-blockchain-*.tar.gz
```

**Option 2: Dropbox**
```bash
dbxcli put tri-blockchain-*.tar.gz /Krystie/TRI/
dbxcli share /Krystie/TRI/tri-blockchain-*.tar.gz
```

**Option 3: Custom Web Server**
```bash
scp tri-blockchain-*.tar.gz user@server:/var/www/html/tri/
# Access at: https://example.com/tri/tri-blockchain-v5.4.4-2026-04-01.tar.gz
```

### Updating Bootstrap Script

After uploading, update `bootstrap.sh`:

```bash
# Edit line 9
BLOCKCHAIN_URL="https://your-url-here/tri-blockchain-latest.tar.gz"
```

Commit and push to make it available to all Pi users!

### Snapshot Contents

**Included:**
- `blk*.dat` - Blockchain data files
- `database/` - Block index
- `txleveldb/` - Transaction index
- `smsgDB/` - Secure messaging database
- `peers.dat` - Known peer cache
- `smsg.ini` - Messaging config

**Excluded (for security/privacy):**
- `wallet.dat` - NEVER include! Contains private keys
- `debug.log` - Large, regenerated on run
- `onion/` - Regenerated automatically
- `tor_data/` - Regenerated automatically

### Maintenance Schedule

**Recommended:** Create new snapshots weekly/monthly as blockchain grows.

Automation example (cron):
```bash
# Every Sunday at 2 AM
0 2 * * 0 /usr/local/bin/create-snapshot.sh && \
          gh release upload v5.4.4 /tmp/tmp.*/tri-blockchain-*.tar.gz --clobber
```

### Compression Stats

Typical compression with tar.gz:
- Original blockchain: ~2-5GB (depends on block height)
- Compressed: ~500MB-1.5GB
- Compression ratio: ~70-75%

### Security Notes

1. **Never include wallet.dat** - Contains private keys!
2. **Verify checksums** - Always provide SHA256 hashes
3. **Trust** - Only use snapshots from trusted sources
4. **Update regularly** - Stale snapshots still require catching up

### Testing

Before releasing publicly:

```bash
# On a fresh Pi
rm -rf ~/.triangles
curl -sSL https://raw.githubusercontent.com/SamiAhmed7777/tri-pi/main/bootstrap.sh | bash
# Choose option 1 (bootstrap download)

# Verify it starts from correct block
trianglesd getinfo | grep blocks
```
