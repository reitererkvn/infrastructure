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

    log "Verarbeite Snapshots in $src_dir..."

    # Check for snapshots
    local snaps=($(ls -d "$src_dir"/[0-9]* 2>/dev/null | sort -V))
    if [[ ${#snaps} -eq 0 ]]; then
        log "  Keine Snapshots in $src_dir gefunden."
        return 0
    fi

    # 1. Neue Snapshots von SSD auf NAS-HDD senden
    for snap in $snaps; do
        id=$(basename "$snap")
        snap_path="$snap/snapshot"

        if [[ ! -d "$snap_path" ]]; then
            continue
        fi

        # Logische Prüfung über SSH: Existiert der Snapshot auf dem NAS bereits?
        if ssh "$NAS_USER@$NAS_IP" "[ -d \"$dst_dir/$id\" ]" 2>/dev/null; then
            log "  ID $id: Bereits auf NAS vorhanden."
        else
            log "  ID $id: Spiegelung auf NAS..."

            # Finde neuesten gemeinsamen Parent-Snapshot, der lokal UND auf dem NAS existiert
            local last_id=""
            for hdd_id in $(ssh "$NAS_USER@$NAS_IP" "ls -1 \"$dst_dir\" 2>/dev/null | grep -E '^[0-9]+$' | sort -nr" 2>/dev/null); do
                if [[ -d "$src_dir/$hdd_id/snapshot" ]]; then
                    last_id="$hdd_id"
                    break
                fi
            done

            if [[ -z "$last_id" ]]; then
                log "    (Initialer Snapshot - Full Send)"
                btrfs send "$snap_path" | ssh "$NAS_USER@$NAS_IP" "sudo btrfs receive \"$dst_dir/\""
            else
                log "    (Inkrementell gegen gemeinsame Parent-ID $last_id)"
                btrfs send -p "$src_dir/$last_id/snapshot" "$snap_path" | ssh "$NAS_USER@$NAS_IP" "sudo btrfs receive \"$dst_dir/\""
            fi

            # Check pipe status (zsh specific)
            if [[ ${pipestatus[1]} -eq 0 && ${pipestatus[2]} -eq 0 ]]; then
                ssh "$NAS_USER@$NAS_IP" "sudo mv \"$dst_dir/snapshot\" \"$dst_dir/$id\""
                log "    ID $id: Erfolgreich übertragen."
            else
                error "Fehler bei der Übertragung von ID $id."
                return 1
            fi
        fi
    done

    # 2. 1:1 Bereinigung: Lösche Snapshots auf der NAS-HDD, die Snapper lokal auf der SSD bereits gelöscht hat
    for hdd_id in $(ssh "$NAS_USER@$NAS_IP" "ls -1 \"$dst_dir\" 2>/dev/null | grep -E '^[0-9]+$' | sort -n" 2>/dev/null); do
        if [[ ! -d "$src_dir/$hdd_id/snapshot" ]]; then
            log "  Bereinige abgelaufenen Snapshot ID $hdd_id auf NAS ($dst_dir)..."
            ssh "$NAS_USER@$NAS_IP" "sudo btrfs subvolume delete \"$dst_dir/$hdd_id\" || sudo rm -rf \"$dst_dir/$hdd_id\"" 2>/dev/null
        fi
    done
}

# Verzeichnisse anlegen, falls sie auf dem NAS noch fehlen
ssh "$NAS_USER@$NAS_IP" "sudo mkdir -p $DEST_BASE/root $DEST_BASE/home"

sync_to_nas "/.snapshots" "$DEST_BASE/root"
sync_to_nas "/home/.snapshots" "$DEST_BASE/home"

log "Sync abgeschlossen. Erstelle Trigger-Datei auf dem NAS..."
ssh "$NAS_USER@$NAS_IP" "sudo touch /var/lib/nas-sync-triggers/homeserver_sync.done"
