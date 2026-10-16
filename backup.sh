
#!/usr/bin/env bash

set -Eeuo pipefail

RETENTION_COUNT=7

fail() {
    local message="$1"

    if [[ -n "${LOG_FILE:-}" ]]; then
        printf '[%s] ERROR: %s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$message" |
            tee -a "$LOG_FILE" >&2
    else
        printf 'ERROR: %s\n' "$message" >&2
    fi
    exit 1
}

log() {
    printf '[%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$*" |
        tee -a "$LOG_FILE"
}

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 SOURCE_DIRECTORY BACKUP_DIRECTORY"
    exit 1
fi

SOURCE_DIR="$1"
BACKUP_DIR="$2"

if [[ ! -d "$SOURCE_DIR" || ! -r "$SOURCE_DIR" ]]; then
    fail "Source directory is missing or unreadable."
fi

SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd -P) ||
    fail "Cannot resolve source directory."

mkdir -p -- "$BACKUP_DIR" ||
    fail "Cannot create backup directory."

BACKUP_DIR=$(cd "$BACKUP_DIR" && pwd -P) ||
    fail "Cannot resolve backup directory."

case "$BACKUP_DIR/" in
    "$SOURCE_DIR/"*)
        fail "Backup directory must not be inside source directory."
        ;;
esac

SOURCE_NAME=$(basename "$SOURCE_DIR")
SAFE_SOURCE_NAME=$(printf '%s' "$SOURCE_NAME" |
    sed 's/[^A-Za-z0-9._-]/_/g')

LOG_FILE="$BACKUP_DIR/backup.log"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
ARCHIVE="$BACKUP_DIR/backup_${TIMESTAMP}_${SAFE_SOURCE_NAME}.tar.gz"

counter=1
while [[ -e "$ARCHIVE" ]]; do
    ARCHIVE="$BACKUP_DIR/backup_${TIMESTAMP}_${counter}_${SAFE_SOURCE_NAME}.tar.gz"
    counter=$((counter + 1))
done

log "Starting backup: $SOURCE_DIR"

if ! tar -czf "$ARCHIVE" \
    -C "$(dirname "$SOURCE_DIR")" "$SOURCE_NAME"; then
    rm -f -- "$ARCHIVE"
    fail "Backup creation failed."
fi

if ! tar -tzf "$ARCHIVE" > /dev/null; then
    rm -f -- "$ARCHIVE"
    fail "Backup integrity verification failed."
fi

log "Backup created and verified: $ARCHIVE"


# Find archives belonging to this source and keep the newest seven.
shopt -s nullglob
archives=("$BACKUP_DIR"/backup_*_"$SAFE_SOURCE_NAME".tar.gz)
shopt -u nullglob

if (( ${#archives[@]} > RETENTION_COUNT )); then
    RETENTION_LIST=$(mktemp) ||
        fail "Cannot create temporary retention list."

    if ! ls -t "${archives[@]}" > "$RETENTION_LIST"; then
        rm -f "$RETENTION_LIST"
        fail "Cannot sort backup archives."
    fi

    count=0

    while IFS= read -r OLD_ARCHIVE; do
        count=$((count + 1))

        # Preserve the seven newest archives.
        if (( count > RETENTION_COUNT )); then
            if rm -- "$OLD_ARCHIVE"; then
                log "Removed old backup: $(basename "$OLD_ARCHIVE")"
            else
                rm -f "$RETENTION_LIST"
                fail "Could not remove old backup: $OLD_ARCHIVE"
            fi
        fi
    done < "$RETENTION_LIST"

    rm -f "$RETENTION_LIST"
fi

