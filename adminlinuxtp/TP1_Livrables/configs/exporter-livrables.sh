#!/usr/bin/bash
set -euo pipefail
mkdir -p TP1/configs TP1/captures
nmcli -f all con show bond0 > TP1/configs/bond0.txt
systemd-analyze plot > TP1/captures/boot-apres.svg
cp -f /root/boot-avant.svg TP1/captures/boot-avant.svg
cp -f /root/boot-apres.svg TP1/captures/boot-apres.svg
