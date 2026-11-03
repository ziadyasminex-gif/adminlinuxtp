# TP2 — Gestion avancée des utilisateurs, permissions, ACL et sudo

**Serveur :** `srv-core` — Rocky Linux 9  
**Contexte :** Hélios Logistique  
**Date des captures :** 3 novembre 2026  
**Livrable :** rapport établi à partir des captures du document `MISSION 2.docx` et de l’énoncé PDF.

> **Note de méthode :** les résultats décrits ci-dessous sont ceux qui sont lisibles dans les captures fournies. Lorsqu'une preuve n'est pas visible ou qu'une sortie est partielle, cela est signalé plutôt que supposé.

## 1. Objectif du TP

Mettre en place un modèle de gestion des accès pour quatre profils : Julien et Nadia (équipe transport), Tarek (télémétrie) et `audit-ext` (auditeur externe en lecture seule). Le TP couvre les comptes et groupes, la politique d'authentification, les bits spéciaux, `umask`, les ACL POSIX et une délégation `sudo` limitée et journalisée.

## 2. Mission 1 — Comptes, groupes et authentification

### 2.1 Politique générale

La configuration montrée dans les captures fixe les paramètres suivants :

| Paramètre | Valeur configurée | Rôle |
|---|---:|---|
| `PASS_MAX_DAYS` | 90 | expiration du mot de passe après 90 jours |
| `PASS_MIN_DAYS` | 1 | délai minimal avant changement |
| `PASS_WARN_AGE` | 14 | avertissement 14 jours avant expiration |
| `UMASK` | 027 | droits par défaut restrictifs |
| `minlen` | 12 | longueur minimale du mot de passe |
| `minclass` | 3 | au moins trois catégories de caractères |
| `maxrepeat` | 3 | limite les répétitions successives |
| `dictcheck` | activé | contrôle dictionnaire |
| `usercheck` | activé | contrôle de similarité avec le nom utilisateur |

La politique de verrouillage `pam_faillock` prévue par l'énoncé est : 5 échecs, fenêtre de 900 secondes, verrouillage de 600 secondes, avec audit. Les captures montrent l'activation du mécanisme, plusieurs tentatives échouées pour `nadia`, puis la remise à zéro avec `faillock --user nadia --reset`.

### 2.2 Groupes et comptes

| Compte | UID | Groupe principal | Groupes secondaires / rôle |
|---|---:|---|---|
| `julien` | 5100 | `transport` (GID 5000) | `helios-ops` (GID 5002), chef d'équipe |
| `nadia` | 5101 | `transport` | exploitante transport |
| `tarek` | 5102 | `telemetry` (GID 5001) | `transport`, analyste télémétrie |
| `audit-ext` | 5103 | `telemetry` | auditeur externe, compte temporaire |

Les groupes créés sont `transport`, `telemetry` et `helios-ops`. Julien est défini comme administrateur du groupe `transport`, puis il ajoute Nadia au groupe. Les captures `getent` et `id nadia` confirment les identifiants et l'appartenance au groupe.

Le compte `audit-ext` est configuré avec une date d'expiration à 21 jours. La capture de `chage` affiche une expiration au **24 novembre 2026**.

### 2.3 Vérifications

- `chage -l julien` montre une politique de 90 jours et un avertissement de 14 jours.
- Une tentative de mot de passe trop court est rejetée par la politique de qualité.
- Les tentatives échouées sur Nadia apparaissent dans `faillock`.
- `faillock --user nadia --reset` vide ensuite la liste des échecs.

**Conclusion :** les comptes et groupes sont créés selon les rôles attendus. La politique de mot de passe et le verrouillage sur échecs sont configurés et testés dans les captures.

## 3. Mission 2 — Bits spéciaux et umask

### 3.1 Héritage du groupe avec setgid

Le répertoire `/srv/helios/projets/transport` est créé avec le mode `2770`, propriétaire `julien` et groupe `transport`. Le bit setgid fait hériter le groupe du répertoire aux nouveaux fichiers.

Le répertoire témoin `/srv/helios/projets/temoin` est créé sans setgid. Le test avec Tarek montre :

- dans `transport/`, `tournee-tarek.csv` appartient au groupe `transport` ;
- dans `temoin/`, le fichier `y` appartient au groupe primaire de Tarek, `telemetry`.

C'est la preuve du fonctionnement du bit setgid sur un répertoire.

### 3.2 Protection du dépôt avec sticky bit

Le répertoire `/srv/helios/depot` est configuré en `1777`. Tarek ne peut pas supprimer le fichier créé par Nadia : l'opération retourne « Opération non permise ».

La capture montre ensuite qu'en passant temporairement le répertoire en `0777`, la suppression réussit. Le mode `1777` est rétabli à la fin. Le sticky bit limite donc la suppression aux propriétaires du fichier, au propriétaire du répertoire et à root.

### 3.3 Tableau umask

| Cas | umask | Mode de fichier attendu | Mode de répertoire attendu | Résultat visible |
|---|---:|---:|---:|---|
| Valeur initiale Nadia | `027` | `640` (`rw-r-----`) | `750` (`rwxr-x---`) | conforme |
| Mode collaboratif | `002` | `664` (`rw-rw-r--`) | `775` (`rwxrwxr-x`) | conforme |
| Mode privé | `077` | `600` (`rw-------`) | non testé dans cette capture | fichier conforme |

La configuration `/etc/profile.d/helios-umask.sh` applique `002` aux membres de `transport` et `027` aux autres utilisateurs. Les captures montrent `umask 0002` pour Nadia et `0027` pour `audit-ext`.

### 3.4 Inventaire setuid/setgid et outil de lecture

L'inventaire `find` affiche notamment les binaires suivants :

- `/usr/bin/passwd` : permet à un utilisateur de modifier son propre mot de passe en mettant à jour des fichiers protégés.
- `/usr/bin/su` : réalise une transition d'identité contrôlée.
- `/usr/bin/mount` : réalise des opérations de montage qui nécessitent des privilèges.

Ces bits spéciaux sont légitimes lorsqu'ils sont portés par des binaires système prévus pour cette fonction et maintenus par le système. Ils doivent néanmoins être audités.

Un outil dédié `helios-lastlog` est compilé et installé avec le groupe `telemetry` et le bit setgid (`2755`). Le fichier de journal `/var/log/helios/app.log` appartient à `root:telemetry` avec des droits `0640`.

Les tests visibles montrent que Julien ne peut pas lire le journal avec `tail` directement, mais peut en lire les dix dernières lignes via `/usr/local/bin/helios-lastlog`. Le `ls -l` confirme le mode `-rwxr-sr-x`.

**Conclusion :** les bits setgid et sticky ont été démontrés en situation réelle. L'umask collaboratif distingue bien les membres du groupe transport des autres utilisateurs.

## 4. Mission 3 — ACL POSIX

### 4.1 Support ACL

La commande `mount` et `xfs_info /` montrent que la racine est sur XFS. XFS prend en charge les ACL POSIX ; aucune option de montage supplémentaire n'est nécessaire.

### 4.2 Accès nominatif de l'auditeur

Une ACL nominative `audit-ext:r-x` est ajoutée au répertoire `/srv/helios/projets/transport`. Les captures montrent que l'auditeur peut lister le répertoire et accéder aux fichiers lisibles, sans être ajouté au groupe `transport`.

Une ACL par défaut est ensuite définie pour que les nouveaux éléments héritent des droits nécessaires :
- `audit-ext` reçoit la lecture ;
- le groupe `transport` conserve les droits de collaboration ;
- les autres utilisateurs n'ont aucun droit.

Le test avec `test-heritage-acl.txt` montre que `audit-ext` peut lire le contenu, mais ne peut pas ajouter du texte. Les tests sur `tournee-j2.csv` et `semaine-41` montrent l'héritage des ACL par défaut.

### 4.3 Effet de `chmod g-w` sur le masque ACL

Sur un fichier porteur d'ACL, `chmod g-w` ne modifie pas uniquement une entrée de groupe apparente : il retire le droit d'écriture de la classe de groupe et met à jour le **masque ACL**. Ce masque limite les permissions effectives des entrées de groupe nommées et des utilisateurs nommés autres que le propriétaire.

La capture montre que l'entrée nominative de Tarek conserve ses permissions demandées, mais que ses permissions effectives perdent l'écriture (`#effective:r-x`). L'écriture de Tarek échoue alors avec « Permission non accordée ».

Après `setfacl -m m::rwx ...`, le masque est élargi et le test d'écriture réussit. Cela démontre que les droits affichés dans une entrée ACL peuvent être supérieurs aux droits effectifs, car ils sont limités par le masque.

### 4.4 Sauvegarde et restauration

Les captures montrent la création de `/root/helios-backup/transport.acl` avec `getfacl -R -p`, puis une opération de restauration avec `setfacl --restore`. La sauvegarde affichée fait environ 1,2 Ko.

La copie de sauvegarde ACL exacte n'a pas été fournie séparément dans le document Word : le fichier `configs/acl-transport-2026-11-03.txt` du présent dossier est donc un **extrait reconstitué à partir des sorties visibles**, et non une copie binaire ou exhaustive de la sauvegarde du serveur. Pour le rendu final, récupérer le fichier original sur `srv-core` si celui-ci est encore présent.

**Conclusion :** les ACL nominatives et par défaut donnent à l'auditeur un accès en lecture seule, et l'expérience `chmod g-w` illustre le rôle du masque ACL.

## 5. Mission 4 — Délégation sudo et traçabilité

### 5.1 Délégation du groupe `helios-ops`

Le fichier `/etc/sudoers.d/90-helios-ops` définit trois alias :
- `HELIOS_SVC` : démarrer, arrêter, redémarrer et consulter l'état du collecteur Helios ; démarrer ou arrêter la cible Helios ;
- `HELIOS_LOG` : consulter les journaux des services Helios concernés ;
- `DANGEREUX` : commandes sensibles exclues de la délégation, notamment `su`, `sudo`, `passwd root`, `vi`, `vim`, `less` et `find`.

La délégation permet également à Julien d'exécuter deux commandes de lecture sous l'identité `helios` pour consulter les données applicatives.

Les paramètres `Defaults` imposent un délai d'authentification de cinq minutes, deux essais de mot de passe, l'affichage de la bannière et la journalisation des sorties.

### 5.2 Tests et journaux

Les captures confirment :
- `visudo -c` valide les fichiers sudoers ;
- `sudo -l -U julien` affiche les commandes autorisées ;
- Julien peut redémarrer `helios-collect.service` ;
- Julien ne peut pas redémarrer `sshd` ;
- Nadia n'appartient pas au groupe `helios-ops` et ne dispose pas de la délégation de Julien ;
- `sudoreplay -l`, `/var/log/sudo-helios.log` et `journalctl -t sudo` montrent des traces de commandes et de sessions.

### 5.3 Règle dangereuse et correction

Une règle de démonstration autorisant Nadia à lancer un éditeur en root sur les fichiers du partage a été ajoutée temporairement. Une telle règle est dangereuse, car un éditeur peut permettre de lancer un shell et donc de contourner la restriction apparente sur le fichier.

La règle temporaire `99-mauvais-exemple` a été supprimée. Elle a été remplacée par une règle `sudoedit` limitée au répertoire de transport dans `91-nadia-edition`. Les captures montrent la validation syntaxique et la liste de droits de Nadia. Les captures ne montrent pas une preuve complète d'évasion de shell exécutée par Nadia ; le rapport ne la présente donc pas comme un test réussi.

**Conclusion :** la délégation de Julien est limitée aux opérations Helios utiles et journalisées. La règle d'éditeur root trop permissive a été retirée et remplacée par `sudoedit`.

## 6. Audit croisé — constats et remédiations

Les constats ci-dessous sont limités aux éléments effectivement visibles dans les captures et aux vérifications effectuées pendant le TP.

| # | Constat | Risque / justification | Remédiation ou contrôle |
|---:|---|---|---|
| 1 | Le dépôt `/srv/helios/depot` est volontairement en `1777`. | Le sticky bit protège la suppression croisée ; conserver ce bit est indispensable. | Vérifier régulièrement `ls -ld /srv/helios/depot` et rétablir `chmod 1777` si nécessaire. |
| 2 | Le partage `transport` utilise setgid et des ACL par défaut. | Une modification du masque ACL peut réduire les droits effectifs des utilisateurs nommés. | Vérifier `getfacl` après tout `chmod` et restaurer le masque voulu avec `setfacl -m m::rwx` si justifié. |
| 3 | Le compte `audit-ext` est temporaire. | Un compte externe doit expirer à la fin du mandat. | Contrôler `chage -l audit-ext` et supprimer/désactiver le compte après le mandat. |
| 4 | La délégation `helios-ops` est ciblée et journalisée. | Une règle sudo trop large peut donner un accès root indirect. | Garder les commandes explicitement listées, valider avec `visudo -c` et contrôler les journaux. |
| 5 | Une règle temporaire d'éditeur root a été utilisée comme exemple de mauvaise pratique. | Un éditeur lancé en root peut offrir une évasion vers un shell privilégié. | Supprimer toute règle `vim`/`vi` générique et préférer `sudoedit` avec un chemin strictement limité. |

## 7. Bilan

Les captures documentent la mise en place des comptes, des groupes, des règles de mot de passe, des bits spéciaux, des umask, des ACL et de la délégation sudo. Les tests les plus importants sont visibles : héritage du groupe `transport`, refus de suppression avec sticky bit, lecture seule de l'auditeur, limitation par le masque ACL, redémarrage autorisé du collecteur et refus du redémarrage de `sshd`.

**Point à compléter avant remise :** joindre la sauvegarde ACL originale exportée depuis `/root/helios-backup/transport.acl` si elle est toujours disponible. Vérifier également que le fichier `91-nadia-edition` est bien la règle active et que `99-mauvais-exemple` n'existe plus.

## 8. Index des captures

Les captures retenues sont rangées dans `captures/` par mission. Les noms de fichiers reprennent leur ordre dans le document Word d'origine.

- Mission 1 : `M1-01` à `M1-08` — politique, comptes, groupes, qualité et verrouillage.
- Mission 2 : `M2-01` à `M2-08` — setgid, sticky, umask, inventaire setuid et outil setgid.
- Mission 3 : `M3-01` à `M3-10` — XFS, ACL nominatives et par défaut, masque et sauvegarde.
- Mission 4 : `M4-01` à `M4-09` — sudoers, tests, journalisation et correction de la règle dangereuse.
