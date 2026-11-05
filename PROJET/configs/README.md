# Configurations effectives

Ce dossier est initialisé volontairement sans faux fichiers de configuration. Les captures ne permettent pas de reconstituer fidèlement toutes les directives et tous les paramètres effectifs.

Depuis `srv-core`, transférer ce dossier puis exécuter :

```bash
sudo bash collecter-configs.sh /chemin/vers/configs
```

Le script copie les unités systemd, le sudoers, la configuration Zabbix, les scripts, les paramètres SSH effectifs et l'état firewalld. Vérifier ensuite le contenu avant de remettre le projet. Les fichiers sensibles sont copiés avec des permissions restrictives.
