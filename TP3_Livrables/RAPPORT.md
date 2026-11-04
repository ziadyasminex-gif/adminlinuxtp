# TP3 — Sécurisation d’un serveur Linux
**Module :** Administration d’un Linux Server — BTC2  
**Environnement :** `srv-core` (serveur cible) et `srv-edge` (poste distant)  
**Objectif :** segmenter le filtrage réseau, renforcer SSH et mettre en place une surveillance des événements avec détection automatisée.

> **Méthode de rédaction :** ce rapport s’appuie sur les captures fournies dans le document Word. Les résultats non visibles dans les captures ne sont pas présentés comme ayant été validés. Les fichiers du dossier `configs/` reprennent les configurations demandées dans l’énoncé ; certains fichiers dont le contenu n’apparaît pas dans les captures sont des modèles de configuration à déployer/vérifier.

## 1. Environnement et état initial

Les captures montrent le serveur `srv-core`, le poste `srv-edge`, le service SSH et le service `firewalld`. Les interfaces métier `bond0` et `bond0.42` ainsi que l’interface d’administration `enp0s8` sont visibles dans les relevés réseau et firewalld.

L’état initial montre SSH actif sur le port 22 et `firewalld` actif. Les captures montrent également la présence de services système et de journaux d’activité.

## 2. Mission 1 — Pare-feu firewalld segmenté par zone

### 2.1 Zones et affectation des interfaces

Les sorties `firewall-cmd --list-all` visibles dans les captures font apparaître les zones suivantes :

| Zone | Interfaces observées | Politique / éléments observés |
|---|---|---|
| `drop` | `enp10`, `enp3`, `enp9` | Cible `DROP` ; service SSH listé |
| `work` | `enp0s8` | Source `192.168.56.0/24` ; services `cockpit`, `dhcpv6-client`, `ssh` |
| `internal` | `bond0`, `bond0.42` | Services `cockpit`, `dhcpv6-client`, `mdns`, `samba-client`, `ssh` ; port `10051/tcp` |

La zone `drop` est bien affichée avec la cible `DROP`. Les interfaces d’administration et métier sont associées respectivement aux zones `work` et `internal`.

**Écart à corriger :** les captures montrent encore plusieurs services dans `work` et `internal` (`cockpit`, `dhcpv6-client`, ainsi que `mdns` et `samba-client` dans `internal`). Or l’énoncé demande de les retirer. La capture montre aussi `enp10`, `enp3` et `enp9` dans `drop`, alors que l’énoncé prévoit `enp0s3` pour l’interface NAT. Il faut vérifier les noms réels des interfaces avec `nmcli` et corriger les profils NetworkManager si nécessaire.

La reconstitution de la sortie observée est fournie dans `configs/zones.txt`. Pour obtenir le relevé exact et à jour, exécuter :

```bash
firewall-cmd --list-all-zones > TP3/configs/zones.txt
```

### 2.2 Règles et vérification nftables

Les captures montrent :
- la table `inet firewalld` ;
- la chaîne `filter_IN_work` ;
- le jeu `helios-blacklist` de type `ipv4_addr` ;
- la couche de compatibilité `iptables-nft`.

Cela confirme que `firewalld` génère des objets nftables et que l’ipset `helios-blacklist` existe. En revanche, la capture de la chaîne ne montre pas la règle riche de limitation SSH attendue, et la sortie `nft list set` montre un ensemble sans entrée affichée.

La tentative de configuration de `--set-log-denied` a d’abord produit une erreur d’usage ; la commande a ensuite été relancée avec `--set-log-denied=unicast` et la valeur `unicast` est affichée. Le réglage est donc visible dans la dernière vérification.

### 2.3 Scan réseau et traces

Le scan Nmap depuis `srv-edge` montre :
- `22/tcp` ouvert (SSH) ;
- `80/tcp` filtré ;
- `10051/tcp` filtré.

Le test `nc` confirme une connexion au port 22 et un délai d’attente sur le port 10051. Les captures de journal montrent des événements associés à des tentatives SSH et des messages de filtrage.

**Limite de preuve :** le TP demande aussi un scan après durcissement et des traces portant explicitement le préfixe `SSH-NEW`. Les captures fournies ne permettent pas d’identifier sans ambiguïté un relevé complet de ces deux preuves après configuration.

## 3. Mission 2 — Durcissement de SSH

### 3.1 Groupe et authentification par clé

La capture montre la création du groupe `ssh-admins`. La première tentative d’ajout de `sysops` échoue car le compte n’existe pas à ce moment-là. Le compte `julien` apparaît ensuite dans le groupe.

Les captures montrent ensuite la copie d’une clé publique Ed25519 pour `sysops` et une connexion réussie depuis `srv-edge` vers `srv-core` par clé. La commande distante retourne le nom d’hôte `srv-core` et les informations d’identité de `sysops`.

### 3.2 Configuration sshd

Le fichier `10-helios-hardening.conf` affiché dans les captures contient notamment :
- port SSH `2242` ;
- écoute IPv4 sur `192.168.56.10` et `10.42.0.10` ;
- interdiction de connexion directe de `root` ;
- authentification par clé publique uniquement ;
- désactivation de l’authentification par mot de passe et clavier interactif ;
- restriction au groupe `ssh-admins` ;
- limitation des tentatives et sessions ;
- désactivation de plusieurs mécanismes de transfert ;
- journalisation `VERBOSE` et bannière `/etc/issue.net` ;
- exception de transfert TCP contrôlée pour `helios-ops` vers `localhost:10051`.

La capture affiche `sshd -t` avec le résultat `Syntaxe OK`, ce qui valide la syntaxe du fichier à cet instant.

### 3.3 Changement de port et tests visibles

Les captures montrent l’ouverture du port `2242` dans les zones firewalld concernées, le retrait du service SSH standard dans `internal`, puis le redémarrage de `sshd`. La sortie `ss -ltnp` montre le démon en écoute sur `192.168.56.10:2242` et `10.42.0.10:2242`.

| Test demandé | Résultat prouvé par les captures |
|---|---|
| Ancien port 22 | `nc` affiche un délai d’attente après changement de port |
| Connexion `sysops` par clé sur 2242 | Une connexion par clé est prouvée avant le changement de port ; le succès après changement de port n’est pas clairement visible |
| Connexion directe `root` | Refusée (`Permission denied (publickey)`) |
| Connexion `nadia` | Refusée (`Permission denied (publickey)`) |
| Mot de passe désactivé | Non démontré par une capture de test dédiée |
| Tunnel TCP restreint | Non démontré par une capture de test dédiée |
| KEX SHA-1 refusé | Non démontré par une capture de test dédiée |

Les journaux SSH visibles contiennent plusieurs événements d’authentification et de refus. Le TP demande les sept tests ; seuls certains résultats sont lisibles dans le dossier de captures. Les tests absents doivent être exécutés et ajoutés au dossier de preuves avant remise.

### 3.4 Politique cryptographique

La capture montre la politique système `DEFAULT`, puis la tentative `DEFAULT:NO-SHA1`. Elle montre également un échec au redémarrage de `sshd` après cette modification. La liste filtrée des algorithmes contient encore des éléments SHA-1, notamment `diffie-hellman-group14-sha1` et `hmac-sha1`.

**Conclusion :** la capture ne permet pas de conclure que le durcissement cryptographique est effectif. Le fichier `05-helios-crypto.conf` fourni reprend l’approche locale proposée par l’énoncé et doit être placé avant `50-redhat.conf`, puis contrôlé avec `sshd -t`, `systemctl restart sshd` et `sshd -T`. Ne pas considérer cette étape comme validée avant un redémarrage réussi et une vérification des algorithmes effectifs.

## 4. Mission 3 — Journaux, audit et détection

### 4.1 Journald persistant

La capture montre la création de `/etc/systemd/journald.conf.d/50-helios.conf` avec :
- `Storage=persistent` ;
- compression activée ;
- limite d’utilisation de 500 Mo ;
- conservation maximale d’un mois ;
- taille maximale de fichier de 50 Mo ;
- scellement des journaux activé.

Après redémarrage de `systemd-journald` et `journalctl --flush`, le répertoire `/var/log/journal/<machine-id>` est présent. `journalctl --disk-usage` affiche environ 8,0 Mo et `journalctl --verify` retourne `PASS` pour les journaux vérifiés.

**Limite de preuve :** l’énoncé exige `journalctl --list-boots` avec au moins deux démarrages. Cette sortie n’est pas visible dans les captures fournies.

### 4.2 Exploitation des journaux et rapports audit

Les captures montrent des rapports `aureport` :
- un rapport global indiquant notamment 37 connexions, 13 échecs de connexion et 26 échecs d’authentification ;
- un rapport d’authentification présentant des comptes tels que `heliosadmin`, `nadia`, `sysops`, `root`, `julien` et `tarek` ;
- un rapport des événements échoués indiquant 13 échecs de connexion et 27 échecs d’authentification ;
- un rapport par clé montrant notamment `privesc` (54 événements), `identity` (36), `sudoers` (4), `sshd-config` (2), `helios-setgid` (2) et `firewall` (1).

Ces éléments montrent que les événements d’audit sont collectés et classés par clé. Ils permettent de repérer les opérations sensibles et les échecs d’authentification.

### 4.3 Détection automatique

Les captures montrent :
- le script `/usr/local/sbin/helios-watch-auth.sh` présent et exécutable ;
- le fichier `helios-watch-auth.service` de type `oneshot` ;
- le timer `helios-watch-auth.timer` configuré avec `OnCalendar=*:0/2`, `Persistent=no` et `AccuracySec=10s` ;
- le timer activé et affiché dans `systemctl list-timers` ;
- des échecs SSH répétés pour l’utilisateur `pirate` ;
- un message du watcher indiquant le blocage de l’adresse `10.42.0.11` après 10 échecs SSH.

**Écart important :** le scénario du TP demande de prouver le blocage de `192.168.56.11`. La capture fournie montre `10.42.0.11` comme adresse bloquée. Le principe de détection et de blocage est visible, mais l’adresse demandée par le formateur n’est pas celle démontrée dans les captures.

Le contenu complet du script n’est pas lisible dans les captures ; le fichier fourni dans `configs/helios-watch-auth.sh` est donc une implémentation conforme aux contraintes de l’énoncé (mode strict, `flock`, tag journald, liste blanche, idempotence et code retour 2 si une instance existe déjà). Il doit être comparé à la version réellement exécutée sur le serveur.

## 5. Bilan des livrables et points à compléter

| Élément demandé | État selon les captures |
|---|---|
| Zones firewalld et liste des zones | Partiellement prouvé ; services supplémentaires encore visibles |
| Chaîne nftables et ipset | Prouvé |
| Scan Nmap | Scan initial prouvé ; scan après durcissement non clairement fourni |
| Traces `SSH-NEW` | Journaux présents, préfixe exact non clairement démontré |
| Drop-in SSH complet | Prouvé |
| `sshd -T` filtré | Partiel ; présence d’algorithmes faibles après échec crypto |
| Port SELinux `2242` (`semanage`) | Non visible |
| Sept tests SSH | Seulement une partie est prouvée |
| Journald persistant et vérification | Prouvé |
| Deux démarrages `journalctl --list-boots` | Non visible |
| Règles auditd et `ausearch -k privesc` | Rapports `aureport` visibles ; sortie `auditctl -l` et `ausearch -k privesc` non clairement isolées |
| Script et timer | Service/timer prouvés ; contenu du script non lisible |
| Blocage de `192.168.56.11` | Non prouvé ; la capture montre `10.42.0.11` |

### Conclusion

Le TP met en évidence la mise en place de plusieurs mécanismes de sécurisation : segmentation firewalld, migration du service SSH vers le port 2242, authentification par clé, conservation persistante des journaux, collecte auditd et déclenchement périodique d’un mécanisme de détection.

Les captures attestent du fonctionnement de plusieurs composants, notamment le démarrage de firewalld, la génération des règles nftables, la connexion SSH par clé avant le changement de port, la syntaxe du drop-in SSH, la persistance de journald, les rapports d’audit et l’activation du timer de surveillance.

Avant la remise définitive, les écarts listés dans le tableau doivent être corrigés ou complétés par des captures supplémentaires. En particulier, il faut vérifier les zones et services, réussir le redémarrage SSH après durcissement cryptographique, effectuer les sept tests depuis `srv-edge`, relever les deux démarrages journald et démontrer le blocage de `192.168.56.11`.
