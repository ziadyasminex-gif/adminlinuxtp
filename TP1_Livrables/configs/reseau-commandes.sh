#!/usr/bin/bash
# Aide-memoire des commandes reseau realisees pour le TP.
# A executer sur les VM concernees en adaptant uniquement si les noms d'interfaces changent.

# srv-core : bond active-backup
nmcli con add type bond con-name bond0 ifname bond0 \
  bond.options "mode=active-backup,miimon=100,primary=enp0s9,fail_over_mac=active" \
  ipv4.method manual ipv4.addresses 10.42.0.10/24 ipv4.never-default yes ipv6.method disabled
nmcli con add type ethernet con-name bond0-p1 ifname enp0s9 master bond0
nmcli con add type ethernet con-name bond0-p2 ifname enp0s10 master bond0
nmcli con up bond0
nmcli con up bond0-p1
nmcli con up bond0-p2

# srv-edge : reseau metier
nmcli con add type ethernet con-name metier ifname enp0s9 \
  ipv4.method manual ipv4.addresses 10.42.0.11/24 ipv4.never-default yes ipv6.method disabled
nmcli con up metier

# srv-core : VLAN 42
nmcli con add type vlan con-name bond0.42 ifname bond0.42 dev bond0 id 42 \
  ipv4.method manual ipv4.addresses 10.42.42.10/24 ipv4.never-default yes ipv6.method disabled
nmcli con up bond0.42

# srv-edge : VLAN 42
nmcli con add type vlan con-name vlan42 ifname enp0s9.42 dev enp0s9 id 42 \
  ipv4.method manual ipv4.addresses 10.42.42.11/24 ipv4.never-default yes ipv6.method disabled
nmcli con up vlan42

# srv-core : routage par politique
grep -qs '^142' /etc/iproute2/rt_tables || echo '142 transport' >> /etc/iproute2/rt_tables
nmcli con mod bond0.42 \
  +ipv4.routes "0.0.0.0/0 10.42.42.11 table=142" \
  +ipv4.routing-rules "priority 100 from 10.42.42.10/32 table 142"
nmcli con up bond0.42

# Export reel demande dans le livrable :
nmcli -f all con show bond0 > bond0.txt
