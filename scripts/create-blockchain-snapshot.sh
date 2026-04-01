#!/bin/bash
# TRI-PI Blockchain Bootstrap Snapshot Creator
# Creates compressed blockchain archive for fast Pi sync

set -e

VERSION="v5.4.4"
SNAPSHOT_DATE=$(date +%Y-%m-%d)
SNAPSHOT_NAME="tri-blockchain-${VERSION}-${SNAPSHOT_DATE}.tar.gz"
TRI_DATA_DIR="$HOME/.triangles"

echo "╔═══════════════════════════════════════╗"
echo "║  TRI-PI Blockchain Snapshot Creator  ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# Check if daemon is running
if pgrep -x trianglesd > /dev/null; then
    echo "⚠️  trianglesd is running. Stopping for clean snapshot..."
    trianglesd stop
    sleep 5
fi

# Check blockchain exists
if [[ ! -d "$TRI_DATA_DIR" ]]; then
    echo "❌ Error: Triangles data directory not found at $TRI_DATA_DIR"
    exit 1
fi

# Get block count from last run
BLOCK_COUNT=$(grep -oP 'height=\K[0-9]+' "$TRI_DATA_DIR/debug.log" 2>/dev/null | tail -1 || echo "unknown")

echo "📊 Blockchain Stats:"
echo "   Location: $TRI_DATA_DIR"
echo "   Block height: $BLOCK_COUNT"
echo "   Size: $(du -sh $TRI_DATA_DIR | cut -f1)"
echo ""

# Create temp directory
TEMP_DIR=$(mktemp -d)
SNAPSHOT_DIR="$TEMP_DIR/triangles-data"
mkdir -p "$SNAPSHOT_DIR"

echo "📦 Creating snapshot..."

# Copy essential blockchain files (exclude wallet and logs)
echo "   • Copying blockchain data..."
cp -r "$TRI_DATA_DIR/blk"* "$SNAPSHOT_DIR/" 2>/dev/null || true
cp -r "$TRI_DATA_DIR/database" "$SNAPSHOT_DIR/" 2>/dev/null || true
cp -r "$TRI_DATA_DIR/txleveldb" "$SNAPSHOT_DIR/" 2>/dev/null || true
cp -r "$TRI_DATA_DIR/smsgDB" "$SNAPSHOT_DIR/" 2>/dev/null || true
cp "$TRI_DATA_DIR/peers.dat" "$SNAPSHOT_DIR/" 2>/dev/null || true
cp "$TRI_DATA_DIR/smsg.ini" "$SNAPSHOT_DIR/" 2>/dev/null || true

# DO NOT include:
# - wallet.dat (user-specific, contains private keys!)
# - debug.log (grows large, not needed)
# - db.log (not needed)
# - onion/ (regenerated on first run)
# - tor_data/ (regenerated)

echo "   • Compressing (this may take a few minutes)..."
cd "$TEMP_DIR"
tar czf "$SNAPSHOT_NAME" triangles-data/

# Calculate size reduction
ORIGINAL_SIZE=$(du -sb "$TRI_DATA_DIR" | cut -f1)
COMPRESSED_SIZE=$(stat -c%s "$SNAPSHOT_NAME")
REDUCTION=$(echo "scale=1; (1 - $COMPRESSED_SIZE / $ORIGINAL_SIZE) * 100" | bc)

echo ""
echo "✅ Snapshot created successfully!"
echo ""
echo "📊 Compression Stats:"
echo "   Original size: $(numfmt --to=iec-i --suffix=B $ORIGINAL_SIZE)"
echo "   Compressed size: $(numfmt --to=iec-i --suffix=B $COMPRESSED_SIZE)"
echo "   Reduction: ${REDUCTION}%"
echo ""
echo "📁 Snapshot file:"
echo "   $TEMP_DIR/$SNAPSHOT_NAME"
echo ""
echo "📝 Metadata:"
cat > "$TEMP_DIR/snapshot-info.txt" << INFO
TRI-PI Blockchain Bootstrap Snapshot
=====================================
Version: $VERSION
Date: $SNAPSHOT_DATE
Block Height: $BLOCK_COUNT
Original Size: $(numfmt --to=iec-i --suffix=B $ORIGINAL_SIZE)
Compressed Size: $(numfmt --to=iec-i --suffix=B $COMPRESSED_SIZE)
Compression: ${REDUCTION}%

SHA256: $(sha256sum "$SNAPSHOT_NAME" | cut -d' ' -f1)

Installation:
1. Extract to ~/.triangles/
2. Start trianglesd
3. Blockchain resumes from block $BLOCK_COUNT

Contents:
- Blockchain files (blk*.dat)
- Database
- Transaction index
- Peer cache
INFO

cat "$TEMP_DIR/snapshot-info.txt"
echo ""
echo "Next steps:"
echo "1. Upload to hosting: scp $TEMP_DIR/$SNAPSHOT_NAME user@server:/path/"
echo "2. Update bootstrap.sh with download URL"
echo "3. Test on fresh Pi"
echo ""
echo "Clean up when done: rm -rf $TEMP_DIR"
