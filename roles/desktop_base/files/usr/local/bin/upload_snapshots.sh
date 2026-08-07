#!/bin/zsh

NAS_IP="192.168.178.46"
NAS_USER="kevin"
DEST_BASE="/mnt/HDD-01/backups/homeserver"
LOG_FILE="/var/log/backup-on-shutdown.log"

# Logging setup
log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

error() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo "$msg" >&2
    echo "$msg" >> "$LOG_FILE"
}

# Ensure log file exists and is writable
touch "$LOG_FILE" 2>/dev/null

if ping -c 3 -W 1 "$NAS_IP" > /dev/null 2>&1; then
    log "OK: $NAS_IP erreichbar. Starte Snapshot-Push..."
else
    error "$NAS_IP nicht erreichbar."
    exit 1
fi

sync_to_nas() {
    local src_dir=$1
    local dst_dir=$2
    local last_snap=""

    log "Verarbeite Snapshots in $src_dir..."

    # Check for snapshots
    local snaps=($(ls -d "$src_dir"/[0-9]* 2>/dev/null | sort -V))
    if [[ ${#snaps} -eq 0 ]]; then
        log "  Keine Snapshots in $src_dir gefunden."
        return 0
    fi

    for snap in $snaps; do
        id=$(basename "$snap")
        snap_path="$snap/snapshot"

        # Logische Prüfung über SSH: Existiert der Snapshot auf dem NAS bereits?
        if ssh "$NAS_USER@$NAS_IP" "[ -d \"$dst_dir/$id\" ]" 2>/dev/null; then
            log "  ID $id: Bereits auf NAS vorhanden."
        else
            log "  ID $id: Spiegelung auf NAS..."

            if [ -z "$last_snap" ]; then
                log "    (Initialer Snapshot - Full Send)"
                btrfs send "$snap_path" | ssh "$NAS_USER@$NAS_IP" "sudo btrfs receive \"$dst_dir/\""
            else
                log "    (Inkrementell gegen ID $(basename $(dirname $last_snap)))"
                btrfs send -p "$last_snap" "$snap_path" | ssh "$NAS_USER@$NAS_IP" "sudo btrfs receive \"$dst_dir/\""
            fi

            # Check pipe status (zsh specific)
            if [[ ${pipestatus[1]} -eq 0 && ${pipestatus[2]} -eq 0 ]]; then
                # Ordner auf dem Zielsystem umbenennen
                ssh "$NAS_USER@$NAS_IP" "sudo mv \"$dst_dir/snapshot\" \"$dst_dir/$id\""
                log "    ID $id: Erfolgreich übertragen."
            else
                error "Fehler bei der Übertragung von ID $id."
                # Wir setzen last_snap trotzdem, falls der nächste Snapshot wieder inkrementell gegen diesen (vllt. lokal korrekten) versucht werden soll?
                # Besser: Abbrechen bei diesem Subvolume, da Inkrement-Kette unterbrochen.
                return 1
            fi
        fi
        last_snap="$snap_path"
    done
}

# Verzeichnisse anlegen, falls sie auf dem NAS noch fehlen
ssh "$NAS_USER@$NAS_IP" "sudo mkdir -p $DEST_BASE/root $DEST_BASE/home"

sync_to_nas "/.snapshots" "$DEST_BASE/root"
sync_to_nas "/home/.snapshots" "$DEST_BASE/home"

log "Sync abgeschlossen. Erstelle Trigger-Datei auf dem NAS..."
ssh "$NAS_USER@$NAS_IP" "sudo touch /var/lib/nas-sync-triggers/homeserver_sync.done"
