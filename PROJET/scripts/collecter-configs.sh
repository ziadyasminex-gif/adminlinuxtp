#!/usr/bin/env bash
set -Eeuo pipefail
OUT="${1:-$PWD/configs}"
mkdir -p "$OUT"/{systemd,sudoers,zabbix,ssh,scripts,firewall}
copy_if_exists() {
  local src="$1" dst="$2"
  if [[ -f "$src" ]]; then install -D -m 0640 "$src" "$OUT/$dst"; fi
}
copy_if_exists /etc/systemd/system/helios-suivi.service systemd/helios-suivi.service
copy_if_exists /etc/systemd/system/helios-suivi-publish.service systemd/helios-suivi-publish.service
copy_if_exists /etc/systemd/system/helios-suivi-publish.timer systemd/helios-suivi-publish.timer
copy_if_exists /etc/systemd/system/helios-suivi-backup.service systemd/helios-suivi-backup.service
copy_if_exists /etc/systemd/system/helios-suivi-backup.timer systemd/helios-suivi-backup.timer
copy_if_exists /etc/sudoers.d/92-helios-suivi sudoers/92-helios-suivi
copy_if_exists /etc/zabbix/zabbix_agent2.d/helios-suivi.conf zabbix/helios-suivi.conf
copy_if_exists /usr/local/sbin/helios-suivi-publish.sh scripts/helios-suivi-publish.sh
copy_if_exists /usr/local/sbin/helios-suivi-backup.sh scripts/helios-suivi-backup.sh
copy_if_exists /etc/ssh/sshd_config ssh/sshd_config
firewall-cmd --list-all-zones > "$OUT/firewall/firewalld-list-all-zones.txt" 2>&1 || true
sshd -T > "$OUT/ssh/sshd-effective.txt" 2>&1 || true
systemd-analyze security helios-suivi.service > "$OUT/systemd/security-score.txt" 2>&1 || true
visudo -c > "$OUT/sudoers/visudo-check.txt" 2>&1 || true
chmod -R go-rwx "$OUT"
echo "Configurations exportées dans : $OUT"
