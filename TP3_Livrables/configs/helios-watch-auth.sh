#!/usr/bin/env bash
# Détection des échecs SSH sur une fenêtre glissante de 10 minutes.
set -Eeuo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin
TAG="helios-watch-auth"
IPSET="helios-blacklist"
STATE_DIR="/var/lib/helios"
BLOCKED_FILE="${STATE_DIR}/blocked.txt"
LOCK_FILE="/run/lock/helios-watch-auth.lock"
WHITELIST=("192.168.56.1")

mkdir -p "$STATE_DIR"
touch "$BLOCKED_FILE"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    logger -t "$TAG" "Une autre instance est déjà en cours."
    exit 2
fi

# Vérifie que l'ipset firewalld existe avant de poursuivre.
if ! firewall-cmd --get-ipsets | tr ' ' '\n' | grep -Fxq "$IPSET"; then
    logger -t "$TAG" "ERREUR : ipset $IPSET introuvable."
    exit 1
fi

is_whitelisted() {
    local candidate="$1" item
    for item in "${WHITELIST[@]}"; do
        [[ "$candidate" == "$item" ]] && return 0
    done
    return 1
}

is_blocked() {
    local candidate="$1"
    grep -Fxq "$candidate" "$BLOCKED_FILE" && return 0
    firewall-cmd --ipset="$IPSET" --get-entries 2>/dev/null | tr ' ' '\n' | grep -Fxq "$candidate"
}

# Les journaux sshd contiennent notamment « Invalid user ... from A.B.C.D ».
mapfile -t offenders < <(
    journalctl -u sshd --since "-10 minutes" -o cat --no-pager 2>/dev/null |
    awk '
      /Failed password|Invalid user|authentication failure/ {
        for (i=1; i<=NF; i++) {
          if ($i=="from" && $(i+1) ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
            print $(i+1)
          }
        }
      }' | sort | uniq -c | awk '$1 > 5 {print $2}'
)

for ip in "${offenders[@]}"; do
    [[ -n "$ip" ]] || continue
    if is_whitelisted "$ip"; then
        logger -t "$TAG" "Adresse $ip ignorée (liste blanche)."
        continue
    fi
    if is_blocked "$ip"; then
        continue
    fi
    if firewall-cmd --ipset="$IPSET" --add-entry="$ip" >/dev/null; then
        grep -Fxq "$ip" "$BLOCKED_FILE" || printf '%s\n' "$ip" >> "$BLOCKED_FILE"
        logger -t "$TAG" "Adresse $ip bloquée après plus de 5 échecs SSH."
    else
        logger -t "$TAG" "ERREUR : impossible d'ajouter $ip à $IPSET."
    fi
done
exit 0
