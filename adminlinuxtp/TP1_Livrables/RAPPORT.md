# TP1 — Configuration avancée du système Linux

**Module :** Administration d'un Linux Server  
**Environnement :** Rocky Linux 9 — `srv-core` et `srv-edge`  
**Entreprise fictive :** Hélios Logistique  
**Étudiant :** À compléter  
**Formateur :** À compléter  
**Date des manipulations :** 2 novembre 2026

---

## 1. Introduction

Ce TP a pour objectif de reprendre l'administration d'un serveur Linux en transformant des tâches manuelles en services supervisés par `systemd`, en mettant en place une redondance réseau et un VLAN métier, puis en automatisant l'archivage de la télémétrie.

Les trois missions réalisées portent sur :
1. la gestion des services, des processus et de la séquence de démarrage ;
2. la configuration réseau avancée (bond, VLAN 802.1Q et routage par règles) ;
3. l'automatisation par script Bash et timer `systemd`.

## 2. Mission 1 — Services, processus et séquence de démarrage

### 2.1 Analyse du démarrage

La capture de `systemd-analyze` indique le résultat suivant :

- noyau : **2,975 s** ;
- initrd : **7,445 s** ;
- espace utilisateur : **9,579 s** ;
- démarrage total : **20,0005 s** ;
- `multi-user.target` atteint après **4,2085 s** dans l'espace utilisateur.

Les commandes `systemd-analyze blame`, `systemd-analyze critical-chain` et `systemd-analyze plot` ont été utilisées pour examiner les unités et produire les représentations SVG avant et après les changements.

Les fichiers `boot-avant.svg` et `boot-apres.svg` sont mentionnés dans les captures comme ayant été générés. Les fichiers SVG originaux ne figuraient toutefois pas dans le document de captures transmis.

**Limite de preuve :** la valeur de démarrage après optimisation n'est pas lisible dans les captures fournies. Il ne faut donc pas annoncer de gain chiffré sans refaire `systemd-analyze` après redémarrage.

### 2.2 Création du service `helios-collect`

Le service `helios-collect.service` exécute le script `/usr/local/sbin/helios-collect.sh` sous le compte système `helios`. Le script ajoute périodiquement dans `/var/lib/helios/telemetry.csv` la date, la charge système et la mémoire disponible.

Le service utilise notamment :
- `Restart=on-failure` et `RestartSec=5s` pour relancer le collecteur en cas d'échec ;
- `NoNewPrivileges=yes`, `PrivateTmp=yes`, `ProtectSystem=strict` et `ProtectHome=yes` pour renforcer l'isolation ;
- `ReadWritePaths` pour limiter les emplacements accessibles en écriture.

Le fichier complet est fourni dans `configs/helios-collect.service` et le script dans `configs/helios-collect.sh`.

### 2.3 Vérification du redémarrage automatique

La capture montre l'envoi du signal `SIGKILL` au service, suivi d'une vérification après sept secondes. Le service apparaît de nouveau **active (running)** avec un nouveau PID. Cela valide le redémarrage automatique configuré dans l'unité.

### 2.4 Surcharge locale et quotas

Une surcharge indépendante du fichier d'origine a été appliquée dans `override.conf` :

```ini
[Service]
Environment=HELIOS_INTERVAL=5
CPUQuota=20%
MemoryMax=96M
IOWeight=50
Nice=5
```

Les propriétés affichées confirment :
- utilisateur : `helios` ;
- groupe : `helios` ;
- priorité Nice : `5` ;
- poids E/S : `50` ;
- limite mémoire : `100663296` octets, soit **96 Mio**.

La capture du contrôle `systemd-analyze security` affiche un score d'exposition global de **5,3 — MEDIUM**. Aucun second score clairement lisible n'est fourni pour établir une comparaison avant/après.

### 2.5 Target métier

La target `helios.target` a été créée et la liste de ses dépendances affiche `helios-collect.service`. Les commandes `systemctl is-enabled` et `systemctl is-active` affichent respectivement `enabled` et `active` pour le service collecteur.

**Conclusion de la mission 1 :** le collecteur est supervisé par systemd, redémarre après arrêt forcé, et ses ressources sont limitées par une surcharge locale. La dépendance à la target métier est visible dans la sortie fournie.

### Captures — Mission 1

| Capture | Preuve |
|---|---|
| `image1.png` | Analyse du démarrage, blame et critical-chain |
| `image2.png` | Score de sécurité 5,3 MEDIUM |
| `image3.png`, `image4.png` | Présence des SVG avant/après et vérification de leur génération |
| `image5.png` | État du service collecteur et surcharge chargée |
| `image6.png` | Paramètres utilisateur, groupe, Nice, IOWeight et MemoryMax |
| `image7.png`, `image8.png` | Temps de démarrage et génération du SVG de vérification |
| `image9.png` | Service activé/actif et dépendances de `helios.target` |
| `image13.png` | Redémarrage du service après SIGKILL |
| `image14.png` | État observé de `helios.target` après arrêt ; la liste des dépendances est la preuve de rattachement |

## 3. Mission 2 — Réseau avancé

### 3.1 Agrégation de liens active-backup

Sur `srv-core`, le bond `bond0` est configuré en mode **active-backup**, avec les interfaces `enp0s9` et `enp0s10`. L'adresse IPv4 du bond est `10.42.0.10/24`.

La sortie de `/proc/net/bonding/bond0` montre :
- mode : `fault-tolerance (active-backup)` ;
- interface esclave principale : `enp0s9` ;
- les deux interfaces avec état MII `up` au moment du contrôle initial ;
- interface active initiale : `enp0s9`.

Sur `srv-edge`, le profil `metier` porte l'adresse `10.42.0.11/24`. Un ping de trois paquets depuis `srv-core` vers `10.42.0.11` reçoit les trois réponses, soit **0 % de perte**.

### 3.2 Test de bascule

La capture prise pendant la coupure montre que l'esclave actif devient `enp0s10`. Les états MII affichés indiquent une interface coupée et l'autre opérationnelle. Cela confirme le changement d'interface active du bond.

**Limite de preuve :** la capture ne montre pas le ping continu pendant toute la bascule ni le nombre exact de paquets ICMP perdus. Le changement d'esclave actif est visible, mais le critère « pas plus de deux requêtes perdues » reste à confirmer avec une capture ping dédiée.

### 3.3 VLAN 802.1Q — ID 42

La sous-interface `bond0.42` a été créée sur `srv-core` avec l'adresse `10.42.42.10/24`. La capture `ip -d link` confirme le protocole VLAN 802.1Q et l'identifiant **42**.

Sur `srv-edge`, la sous-interface `enp0s9.42` est configurée avec l'adresse `10.42.42.11/24`.

Le ping entre `10.42.42.10` et `10.42.42.11` reçoit trois réponses sur trois, soit **0 % de perte**. La capture `tcpdump` montre des trames marquées `vlan 42` et des paquets ICMP entre les deux adresses.

### 3.4 Routage par règles

La table `142 transport` a été ajoutée dans `/etc/iproute2/rt_tables`. Une règle de priorité 100 sélectionne cette table pour les paquets ayant comme adresse source `10.42.42.10`.

Les résultats observés sont :

```text
100: from 10.42.42.10 lookup transport proto static
default via 10.42.42.11 dev bond0.42 table transport
```

La commande `ip route get 8.8.8.8 from 10.42.42.10` indique une sortie via la passerelle `10.42.42.11`, l'interface `bond0.42` et la table `transport`.

Sans adresse source imposée, `ip route get 8.8.8.8` indique une sortie via `10.0.2.2` sur `enp0s3`. Une capture après redémarrage confirme que la règle et la route de la table transport sont toujours présentes.

**Conclusion de la mission 2 :** le bond active-backup, le VLAN 42, la communication entre les deux VM et le routage par politique sont démontrés par les captures. La persistance de la règle et de la route après redémarrage est également visible.

### Captures — Mission 2

| Capture | Preuve |
|---|---|
| `image10.png` | État initial du bond et de ses deux esclaves |
| `image11.png` | Configuration du réseau métier sur `srv-edge` |
| `image12.png` | Ping réseau métier : 0 % de perte |
| `image15.png` | Bascule de l'esclave actif vers `enp0s10` |
| `image16.png` | Création de `bond0.42` et identification VLAN 42 |
| `image17.png` | Ping sur le VLAN 42 : 0 % de perte |
| `image18.png` | Capture tcpdump de trames VLAN 42 |
| `image19.png`, `image20.png` | Règle de routage, table transport et choix des routes |
| `image21.png` | Vérification de la persistance après redémarrage |

## 4. Mission 3 — Automatisation

### 4.1 Script robuste d'archivage

Le script `helios-archive.sh` archive le fichier `/var/lib/helios/telemetry.csv` dans `/var/lib/helios/archives`, compresse l'archive avec gzip et supprime les archives dépassant la durée de rétention configurée à 14 jours.

Les mécanismes présents sont :
- mode strict Bash : `set -euo pipefail` ;
- verrou exclusif non bloquant avec `flock` ;
- nettoyage avec `trap` à la sortie ;
- journalisation via `logger` dans journald ;
- codes retour explicites : `0` succès, `2` verrou déjà pris, `3` prérequis manquant.

### 4.2 Tests des codes retour

Les captures et les journaux montrent les trois résultats attendus :

| Code retour | Situation testée | Résultat |
|---:|---|---|
| `0` | Archivage normal | Succès |
| `2` | Une autre instance détient le verrou | Verrou déjà pris |
| `3` | Fichier source absent/illisible | Prérequis manquant |

Les journaux montrent également la création d'une archive compressée, le nombre de lignes archivées, la purge et le code retour de fin d'exécution.

### 4.3 Service et timer systemd

Le service `helios-archive.service` est de type `oneshot`. Il exécute le script d'archivage avec une priorité Nice de 10 et une classe d'ordonnancement E/S `idle`.

Le timer `helios-archive.timer` est programmé quotidiennement à **02:30** avec :
- `AccuracySec=1min` ;
- `RandomizedDelaySec=120` ;
- `Persistent=yes`, afin de rattraper une exécution manquée pendant l'arrêt de la VM.

La sortie de `systemd-analyze calendar` confirme les prochaines occurrences à 02:30. La liste des timers indique une prochaine exécution le **3 novembre 2026 à 02:31:50 CET**. Le lancement manuel du service se termine avec `status=0/SUCCESS`, et le timer est indiqué comme actif.

### 4.4 Comparaison observée : cron et systemd timer

| Critère demandé | systemd timer — observations du TP | cron — observations du TP |
|---|---|---|
| Rattrapage après VM éteinte | `Persistent=yes` est configuré ; le comportement de rattrapage n'a pas été testé par un arrêt couvrant l'heure planifiée. | Aucun mécanisme de rattrapage n'est démontré dans les captures. |
| Journalisation et corrélation | Journaux consultables avec `journalctl` ; le service et le timer sont identifiés par leurs unités. | La capture montre le démarrage de `crond` et la consultation de son journal, sans journal d'exécution du script cron fourni. |
| Expression de dépendances | Dépendances explicites dans les unités `.service` et `.timer`. | La crontab présente une commande planifiée, sans dépendances systemd équivalentes montrées. |
| Limitation de ressources | `Nice=10` et `IOSchedulingClass=idle` sont définis dans le service oneshot. | Aucune limitation équivalente n'est démontrée dans l'entrée cron. |
| Dispersion de la charge | `RandomizedDelaySec=120` ajoute une dispersion maximale de 120 secondes. | Aucune dispersion n'est configurée dans l'entrée cron montrée. |
| Interrogation de la prochaine exécution | `systemctl list-timers` affiche la prochaine date et heure (`NEXT`). | Aucun affichage équivalent de la prochaine exécution n'est montré dans les captures. |

Le fichier cron temporaire a ensuite été supprimé et la capture finale confirme que `helios-archive.timer` reste actif.

### Captures — Mission 3

| Capture | Preuve |
|---|---|
| `image22.png` | Permissions du script d'archivage |
| `image23.png` | Code retour 0 |
| `image24.png` | Code retour 2 lorsque le verrou est détenu |
| `image25.png` | Préparation du test de source absente et code retour 3 |
| `image26.png` | Restauration du fichier source et redémarrage du collecteur |
| `image27.png` | Journaux journald des trois scénarios |
| `image28.png` | Calendrier du timer et prochaine exécution |
| `image29.png` | Exécution manuelle réussie du service oneshot |
| `image30.png` | Installation/activation de cron et test de la configuration temporaire |
| `image31.png` | Suppression de l'entrée cron temporaire et timer systemd actif |

## 5. Fichiers de configuration fournis

Le dossier `configs/` contient :
- `helios-collect.service` ;
- `helios-collect.sh` ;
- `override.conf` ;
- `helios.target` ;
- `helios-archive.sh` ;
- `helios-archive.service` ;
- `helios-archive.timer` ;
- `helios-inbox.path` (bonus) ;
- `reseau-commandes.sh` ;
- `exporter-livrables.sh`.

**À compléter sur la VM avant remise :**
1. Exécuter `nmcli -f all con show bond0 > bond0.txt` pour produire la vraie sortie complète de NetworkManager. Le fichier `configs/bond0.txt` fourni est uniquement une note explicative et ne remplace pas cette sortie.
2. Copier les fichiers SVG réellement générés `boot-avant.svg` et `boot-apres.svg` dans `captures/`. Ils ne sont pas intégrés au document Word reçu.
3. Si le formateur exige la preuve du nombre de paquets perdus lors de la bascule, refaire le test avec un ping continu enregistré pendant la coupure.
4. Compléter le tableau cron/timer par un test réel de rattrapage après arrêt de la VM si ce critère doit être prouvé expérimentalement.

## 6. Conclusion générale

Ce TP a permis de mettre en place un collecteur de télémétrie supervisé par `systemd`, de limiter ses ressources et de vérifier son redémarrage après arrêt forcé. La configuration réseau apporte une redondance active-backup, un VLAN transport 802.1Q et un routage par politique persistant après redémarrage. Enfin, le script Bash d'archivage a été testé avec les trois codes retour demandés, puis planifié avec un timer systemd.

Les captures démontrent le fonctionnement principal des trois missions. Les éléments signalés dans la section 5 restent à exporter ou à tester pour que le dossier de rendu soit entièrement conforme à la liste des livrables du sujet.
