#!/bin/bash
exec > /var/log/pam-bw-unlock.log 2>&1
set -x

if [ "$PAM_USER" != "kevin" ]; then
    exit 0
fi

read -r PASSWORD
export BW_PASSWORD="$PASSWORD"
export HOME=/root

SESSION_DIR="/run/vault"
SESSION_FILE="$SESSION_DIR/bw_session"

mkdir -p "$SESSION_DIR"
chown kevin:kevin "$SESSION_DIR"
chmod 755 "$SESSION_DIR"

BW_SESSION_TMP=$(/usr/bin/bw unlock --passwordenv BW_PASSWORD --raw)

if [ $? -eq 0 ] && [ -n "$BW_SESSION_TMP" ]; then
    printf "%s" "$BW_SESSION_TMP" > "$SESSION_FILE"
    chmod 600 "$SESSION_FILE"
    chown kevin:kevin "$SESSION_FILE"
fi

exit 0
