# Projet — Mise en production du portail de suivi des tournées Helios

**Serveur principal :** `srv-core`  
**Serveur de test réseau :** `srv-edge`  
**Système :** Rocky Linux 9  
**Date des dernières preuves :** 5 novembre 2026

## 1. Objet

Ce projet met en production un portail local de suivi des tournées Helios. Il couvre la gestion des comptes et groupes, les permissions POSIX/ACL, la publication du contenu, le service systemd, la délégation sudo, le filtrage réseau, le durcissement SSH, la supervision Zabbix/sysstat et la sauvegarde/restauration.

Les preuves retenues dans `preuves/` sont une sélection des captures fournies dans le document Word. Les captures redondantes ou peu lisibles ont été écartées.

## 2. Synthèse de conformité

| Exigence | Résultat documenté | État |
|---|---|---|
| E1 — Comptes et groupes | Groupe `suivi` GID 5003, compte `lea` UID 5104, vieillissement du mot de passe, compte système `helios-suivi` sans shell interactif | Réalisé selon captures |
| E2 — Droits et ACL | Répertoire web `root:suivi`, mode setgid `2770`, ACL pour `helios-suivi`, création de `index.html` par `lea`, lecture par le compte de service | Réalisé selon captures |
| E3 — Publication | Publication exécutée et journalisée sous le tag `helios-suivi-publish` | Partiellement documenté : script complet à archiver |
| E4 — Service systemd sécurisé | Captures de configuration et de tests du service présentes | À confirmer avec les fichiers réels exportés et le contrôle du score de sécurité |
| E5 — Sudoers | Des éléments de configuration figurent dans les captures/archives | À confirmer par validation de `visudo -c` et tests des commandes autorisées/interdites |
| E6 — Pare-feu | Zone par défaut `drop`; tests depuis `srv-edge` : accès autorisé au réseau interne et timeout depuis l'adresse d'administration | Réalisé selon captures |
| E7 — SSH | `Port 2242`, `PermitRootLogin no`, `PasswordAuthentication no`, `AllowGroups ssh-admins` | Configuration attestée; refus SSH de `lea` à conserver comme preuve complémentaire si absent |
| E8 — Supervision | Agent Zabbix actif/activé, timer sysstat actif, `zabbix_get` retourne HTTP `200` et âge de l'état | Réalisé selon captures |
| E9 — Sauvegarde/restauration | Archive, checksum, timer quotidien 03:15 `Persistent=yes`, test de restauration et ACL vérifiées | Réalisé; dernière exécution systemd validée le 05/11/2026 à 14:32 |
| E10 — Audit bonus | Aucune preuve suffisante identifiée | Non documenté / optionnel |

> **Important :** les états « à confirmer » ne sont pas déclarés conformes sans preuve explicite. Les captures montrent des résultats de commandes, mais ne remplacent pas l'export des fichiers de configuration effectifs du serveur.

## 3. Réalisation

### E1 — Comptes et groupes

Le groupe `suivi` est créé avec le GID `5003`. Le compte `lea` utilise l'UID `5104` et le groupe principal `suivi`. Les paramètres de vieillissement du mot de passe sont définis avec `chage`. Le compte de service `helios-suivi` est un compte système dont le shell est `/sbin/nologin` et dont le répertoire personnel est `/srv/helios/suivi`.

**Preuves :** `preuves/E1_comptes_groupes/`.

### E2 — Permissions et ACL

Le répertoire `www` est détenu par `root:suivi` et reçoit le mode `2770`, qui active le bit setgid afin de conserver le groupe du répertoire pour les nouveaux éléments. Des ACL sont appliquées au compte de service. Le fichier `index.html` est créé par `lea` et le compte `helios-suivi` peut le lire.

**Preuves :** `preuves/E2_droits_acl_portail/`.

### E3 — Publication

Les captures montrent une exécution réussie du mécanisme de publication et un message de réussite dans le journal avec le tag `helios-suivi-publish`.

**Preuves :** `preuves/E3_publication_journald/`.

Le script de publication doit être exporté depuis `/usr/local/sbin/helios-suivi-publish.sh` dans `configs/` ou `scripts/` avant remise définitive.

### E4 — Service systemd

Les captures de cette section documentent la mise en place et les vérifications du service portail. Le contrôle final doit être fait sur la machine avec les commandes ci-dessous, puis les fichiers réels doivent être exportés :

```bash
systemctl cat helios-suivi.service
systemctl cat helios-suivi-publish.service
systemctl cat helios-suivi-publish.timer
systemd-analyze security helios-suivi.service
systemctl is-enabled helios-suivi.service helios-suivi-publish.timer
```

**Preuves :** `preuves/E4_service_securisation/`.

### E5 — Délégation sudo

La délégation doit rester limitée aux opérations demandées par le sujet (redémarrage/état du portail, lancement du service de publication et consultation bornée des journaux). Le fichier effectif attendu dans ce projet est `/etc/sudoers.d/92-helios-suivi`.

Vérifications à joindre au dossier :

```bash
visudo -c
cat /etc/sudoers.d/92-helios-suivi
sudo -l -U lea
```

**État :** à confirmer sur le serveur avant remise finale.

### E6 — Pare-feu et segmentation

Les captures attestent que la zone par défaut est `drop`, que le port `8080/tcp` n'est pas ouvert dans les zones non prévues et que le test depuis le réseau d'administration aboutit à un timeout. Le test positif depuis `srv-edge` est inclus dans le lot de captures.

**Preuves :** `preuves/E6_firewall_tests/`.

### E7 — Durcissement SSH

Les paramètres effectifs relevés par `sshd -T` sont :

```text
port 2242
permitrootlogin no
passwordauthentication no
allowgroups ssh-admins
```

Les captures associées sont dans `preuves/E7_ssh_durcissement/`. Pour une preuve complète, joindre également le test de refus de connexion SSH du compte `lea` et l'événement correspondant dans le journal SSH si ces éléments ne figurent pas déjà dans les captures.

### E8 — Supervision

Les captures montrent `zabbix-agent2` actif et activé, le timer `sysstat-collect.timer` actif, ainsi que des retours Zabbix pour les clés de supervision du portail : HTTP `200` et âge de l'état (en secondes).

**Preuves :** `preuves/E8_supervision_zabbix_sysstat/`.

### E9 — Sauvegarde et restauration

Le répertoire d'archives est `/srv/helios/archives/suivi`. Le script crée une archive compressée avec conservation des ACL et attributs étendus, calcule un SHA256, et applique une rétention de sept archives au maximum. Le timer `helios-suivi-backup.timer` est activé et planifié à 03:15 avec `Persistent=yes`.

Le 5 novembre 2026 à 14:32, l'exécution via systemd a retourné `status=0/SUCCESS`, créé l'archive `suivi-20261105-143219.tar.gz` et validé son empreinte (`Réussi`). Trois archives étaient présentes lors du contrôle, donc sous la limite de sept. Le test de restauration et la comparaison ACL avaient également été réalisés précédemment.

**Preuves antérieures :** `preuves/E9_sauvegarde_restauration/`.  
**Dernières preuves à ajouter :** captures du terminal de la conversation montrant `status=0/SUCCESS`, `sha256sum ... Réussi`, compteur `3`, et timer `enabled` / prochaine exécution à `03:15`. Ces captures ne sont pas dans le document Word transmis ici.

## 4. Justifications techniques

1. **Compte de service dédié :** `helios-suivi` sépare l'exécution du portail des comptes humains et son shell `/sbin/nologin` limite les connexions interactives.
2. **Setgid et ACL :** le mode `2770` conserve le groupe `suivi` sur les nouveaux fichiers du répertoire partagé; les ACL accordent les accès nécessaires au service sans ouvrir les données à tous les utilisateurs.
3. **Sauvegarde vérifiable :** l'archive inclut les ACL et attributs étendus; le fichier SHA256 permet de détecter une altération, tandis que le test de restauration valide l'exploitabilité de la sauvegarde.

## 5. Mesures et limites

Les valeurs exactes de charge CPU/mémoire `sar` et les métriques de consommation du service ne sont pas retranscrites ici faute de preuve suffisamment lisible et vérifiable dans les captures sélectionnées. Les ajouter depuis le serveur avant remise si le sujet l'exige.

Les captures documentent une grande partie des exigences, mais les fichiers de configuration effectifs doivent être exportés avec le script fourni dans `scripts/collecter-configs.sh`. Les sections E4 et E5, ainsi que le test de refus SSH E7, sont à contrôler sur le serveur avant de déclarer la conformité totale.

## 6. Commandes de vérification finale

```bash
# Services
systemctl is-active helios-suivi.service zabbix-agent2
systemctl is-enabled helios-suivi.service helios-suivi-publish.timer helios-suivi-backup.timer

# Pare-feu
firewall-cmd --get-default-zone
firewall-cmd --zone=internal --query-port=8080/tcp

# SSH
sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|allowgroups) '

# Sudoers
visudo -c
sudo -l -U lea

# Sauvegarde
systemctl status helios-suivi-backup.service --no-pager -l
systemctl is-enabled helios-suivi-backup.timer
systemctl list-timers --all | grep helios-suivi-backup
cd /srv/helios/archives/suivi && sha256sum -c "$(ls -t *.sha256 | head -1)"
find /srv/helios/archives/suivi -maxdepth 1 -type f -name 'suivi-*.tar.gz' | wc -l
```

## 7. Arborescence du livrable

```text
PROJET/
├── RAPPORT.md
├── RUNBOOK.md
├── configs/
│   └── README.md
├── scripts/
│   └── collecter-configs.sh
└── preuves/
    ├── E1_comptes_groupes/
    ├── E2_droits_acl_portail/
    ├── E3_publication_journald/
    ├── E4_service_securisation/
    ├── E6_firewall_tests/
    ├── E7_ssh_durcissement/
    ├── E8_supervision_zabbix_sysstat/
    └── E9_sauvegarde_restauration/
```
