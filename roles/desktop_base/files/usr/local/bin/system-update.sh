#!/bin/bash
# Arch Linux Maintenance Protocol v4 (POSIX Compliant & Linted)
# OS: EndeavourOS (Arch) | Filesystem: Btrfs

set -u
CLEANUP_MODE=0

# Signal-Parsing für Argumente
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--cleanup) CLEANUP_MODE=1 ;;
        -h|--help)
            echo "Nutzung: $0 [-c|--cleanup]"
            echo "Standardmäßig wird KEIN Cleanup durchgeführt."
            exit 0
            ;;
        *) echo "Unbekanntes Signal: $1"; exit 1 ;;
    esac
    shift
done

echo "========================================"
echo " SYSTEM UPDATE INITIATED"
echo "========================================"

# Schritt 1: System-Update
echo ">>> [1/2] System-Update wird ausgeführt..."
if ! paru -Syu; then
    echo ">>> [!] Update fehlgeschlagen. Versuche Keyrings zu aktualisieren und wiederhole..."
    # pacman statt paru verwenden, um GPG-Probleme direkter zu beheben
    if sudo pacman -Sy --noconfirm archlinux-keyring cachyos-keyring; then
        echo ">>> Keyrings erfolgreich aktualisiert. Zweiter Update-Versuch..."
        if ! paru -Su; then
            echo ">>> [X] Zweiter Versuch ebenfalls fehlgeschlagen. Abbruch."
            exit 1
        fi
    else
        echo ">>> [X] Keyring-Update fehlgeschlagen. Abbruch."
        exit 1
    fi
fi

# Schritt 2: Verwaiste Pakete (Orphans)
echo ">>> [2/3] Suche nach verwaisten Paketen (Orphans)..."
ORPHANS=$(pacman -Qtdq)
if [ -n "$ORPHANS" ]; then
    echo "    -> Folgende verwaiste Pakete wurden gefunden:"
    echo "$ORPHANS" | sed 's/^/       - /'
    echo ""
    if [[ $CLEANUP_MODE -eq 1 ]]; then
        echo ">>> Override-Signal (-c) detektiert. Entferne verwaiste Pakete automatisch..."
        sudo pacman -Rns $ORPHANS --noconfirm
    else
        read -r -p "Sollen diese verwaisten Pakete jetzt deinstalliert werden? (j/N): " orphan_choice
        if [[ "$orphan_choice" =~ ^[jJ]$ ]]; then
            sudo pacman -Rns $ORPHANS --noconfirm
            echo "    -> Verwaiste Pakete erfolgreich entfernt."
        else
            echo "    -> Übersprungen."
        fi
    fi
else
    echo "    -> Keine verwaisten Pakete gefunden."
fi
echo ""

# Schritt 3: Speichermanagement (Verbose Analyse & Ausführung)
echo ">>> [3/3] System-Diagnose für Speichermanagement..."

if [[ $CLEANUP_MODE -eq 1 ]]; then
    echo ">>> Override-Signal (-c) detektiert. Überspringe Diagnose."
    EXECUTE_CLEANUP=1
else
    echo "    -> Analysiere Pacman-Cache (Lösch-Kandidaten):"
    if command -v paccache &> /dev/null; then
        # Nutzt eine prozess-effiziente while-Schleife statt sed-Pipes
        while IFS= read -r line; do
            if [[ "$line" =~ \.pkg\.tar\.(zst|xz) ]]; then
                echo "       - $line"
            fi
        done < <(sudo paccache -d -v 2>/dev/null)
    fi

    echo ""
    echo "    -> Analysiere AUR-Cache (zu löschende Build-Verzeichnisse):"
    AUR_DIRS=$(find "$HOME/.cache/paru/clone" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

    if [ -n "$AUR_DIRS" ]; then
        # Effiziente Formatierung ohne sed
        while IFS= read -r dir; do
            if [ -n "$dir" ]; then
                echo "       - $(basename "$dir")"
            fi
        done <<< "$AUR_DIRS"

        # shellcheck disable=SC2086
        AUR_SIZE=$(du -shc $AUR_DIRS 2>/dev/null | grep total | cut -f1)
        echo "       Gesamter potenzieller Speichergewinn (AUR): $AUR_SIZE"
    else
        echo "       AUR-Cache enthält keine temporären Build-Verzeichnisse."
    fi

    echo ""
    # SC2162 behoben: -r Flag hinzugefügt
    read -r -p "Sollen diese aufgelisteten Dateien nun von der NVMe-SSD gelöscht werden? (j/N): " cleanup_choice
    if [[ "$cleanup_choice" =~ ^[jJ]$ ]]; then
        EXECUTE_CLEANUP=1
    else
        EXECUTE_CLEANUP=0
    fi
fi

# Ausführung & Delta-Messung
if [[ $EXECUTE_CLEANUP -eq 1 ]]; then
    echo ">>> Führe physikalische Löschung aus..."

    FREED_PACMAN="0 B"
    FREED_AUR_MB="0.00"

    echo "    -> Räume Pacman-Cache auf..."
    if command -v paccache &> /dev/null; then
        PAC_OUT=$(sudo paccache -r -v)
        while IFS= read -r line; do
            if [[ ! "$line" =~ "==>" ]] && [[ ! "$line" =~ "finished" ]] && [ -n "$line" ]; then
                echo "       - $line"
            fi
        done <<< "$PAC_OUT"

        EXTRACTED_PACMAN=$(echo "$PAC_OUT" | grep "disk space saved" | awk -F': ' '{print $2}' | tr -d ')')
        if [[ -n "$EXTRACTED_PACMAN" ]]; then FREED_PACMAN="$EXTRACTED_PACMAN"; fi
    fi

    echo "    -> Entferne AUR-Build-Verzeichnisse..."
    AUR_DIRS_BEFORE=$(find "$HOME/.cache/paru/clone" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    if [ -n "$AUR_DIRS_BEFORE" ]; then
        # shellcheck disable=SC2086
        AUR_KB_BEFORE=$(du -skc $AUR_DIRS_BEFORE 2>/dev/null | grep total | cut -f1)
    else
        AUR_KB_BEFORE=0
    fi

    paru -Scc --aur --noconfirm > /dev/null 2>&1

    AUR_DIRS_AFTER=$(find "$HOME/.cache/paru/clone" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    if [ -n "$AUR_DIRS_AFTER" ]; then
        # shellcheck disable=SC2086
        AUR_KB_AFTER=$(du -skc $AUR_DIRS_AFTER 2>/dev/null | grep total | cut -f1)
    else
        AUR_KB_AFTER=0
    fi

    DELTA_KB=$((AUR_KB_BEFORE - AUR_KB_AFTER))
    if [ $DELTA_KB -lt 0 ]; then DELTA_KB=0; fi
    FREED_AUR_MB=$(awk "BEGIN {printf \"%.2f\", $DELTA_KB/1024}")

    if [ -n "$AUR_DIRS_BEFORE" ]; then
        while IFS= read -r dir; do
            if [ -n "$dir" ]; then
                echo "       - $(basename "$dir")"
            fi
        done <<< "$AUR_DIRS_BEFORE"
    fi

    echo ">>> Speichermanagement erfolgreich abgeschlossen."
    echo ""
    echo "========================================"
    echo " BERICHT: FREIGEGEBENER SPEICHER "
    echo "========================================"
    echo " -> Pacman (Core): $FREED_PACMAN"
    echo " -> AUR (Builds):  ${FREED_AUR_MB} MB"
    echo "========================================"
else
    echo ">>> Traceability Mode aktiv. Löschvorgang abgebrochen."
fi

echo "========================================"
echo " SYSTEM UPDATE COMPLETE. "
echo "========================================"

# SC2162 behoben: -r Flag hinzugefügt
read -r -p "Drücke [ENTER], um die Konsole zu terminieren..."
