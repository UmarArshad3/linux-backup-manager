
#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_SCRIPT="$PROJECT_DIR/backup.sh"
TEST_ROOT=$(mktemp -d)

trap 'rm -rf "$TEST_ROOT"' EXIT

SOURCE="$TEST_ROOT/source"
DEST="$TEST_ROOT/backups"

mkdir -p "$SOURCE"
echo "Automated backup test" > "$SOURCE/example.txt"

echo "Test 1: Create a backup"
"$BACKUP_SCRIPT" "$SOURCE" "$DEST"

ARCHIVE_COUNT=$(find "$DEST" -maxdepth 1 \
    -type f -name 'backup_*.tar.gz' | wc -l | tr -d ' ')

[[ "$ARCHIVE_COUNT" -eq 1 ]] || {
    echo "FAIL: Expected one backup, found $ARCHIVE_COUNT"
    exit 1
}
echo "PASS: Backup created"

echo "Test 2: Verify archive contents"
tar -tzf "$DEST"/*.tar.gz | grep -q 'example.txt'
echo "PASS: Archive contains expected file"

echo "Test 3: Reject missing source"
if "$BACKUP_SCRIPT" "$TEST_ROOT/missing" "$DEST"; then
    echo "FAIL: Missing source was accepted"
    exit 1
fi
echo "PASS: Missing source rejected"

echo "Test 4: Retain seven backups"
for i in {1..7}; do
    sleep 1
    "$BACKUP_SCRIPT" "$SOURCE" "$DEST" > /dev/null
done

ARCHIVE_COUNT=$(find "$DEST" -maxdepth 1 \
    -type f -name 'backup_*.tar.gz' | wc -l | tr -d ' ')

[[ "$ARCHIVE_COUNT" -eq 7 ]] || {
    echo "FAIL: Expected seven backups, found $ARCHIVE_COUNT"
    exit 1
}

echo "PASS: Seven-backup retention verified"
echo "All tests passed!"

