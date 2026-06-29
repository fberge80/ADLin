# Contribuer à ADLin

Merci de votre intérêt pour le projet ADLin. Ce document décrit le processus
de contribution et les standards de qualité attendus.

## Principes directeurs

- **ITIL-first** : toute modification doit respecter les pratiques ITIL 4
  (gestion des changements, déploiements, configuration)
- **KISS** : Keep It Simple — pas de sur-ingénierie
- **SELinux enforcing** : aucun contournement de SELinux sur Rocky Linux 9
- **Idempotence Ansible** : toute tâche doit pouvoir être rejouée sans effet
  de bord

## Cycle de contribution

1. **Ouvrir une issue** avec le template `bug_report` ou `feature_request`
2. **Discuter** de l'approche dans l'issue avant de coder
3. **Créer une branche** : `git checkout -b fix/xxx` ou `feature/xxx`
4. **Coder** en respectant les conventions du projet
5. **Tester** : `make lint` doit passer sans erreur
6. **Ouvrir une Pull Request** vers `master`

## Conventions de code

### Ansible

- **FQCN obligatoire** : `ansible.builtin.command`, pas `command`
- **Noms de tâches** : `"Rôle | Action descriptive"` (ex: `"Common | SELinux enforcing"`)
- **Variables enregistrées** : préfixées par le rôle (`common_*`, `nextcloud_*`)
- **Tags** : chaque `import_tasks` doit avoir des tags
- **Secrets** : `no_log: true` sur toute tâche manipulant des mots de passe

### YAML

- Indentation : 2 espaces
- Longueur de ligne : max 160 caractères
- Guillemets : obligatoires pour les chaînes contenant `{}`, `:`, `#`

### Messages de commit

Format libre mais descriptif. Exemples :
```
freeipa_client: remplace dig par getent hosts (compatibilité Rocky minimal)
rocketchat: corrige le tag d'image Docker (8 -> 8.5.1)
docs: ajoute la procédure d'enrollment pbx01
```

## Vérifications avant PR

```bash
make lint                    # yamllint + ansible-lint (doit passer)
make check-collections       # toutes les collections installées
git diff --check             # pas de whitespace trailing
```

## Structure des rôles

Chaque rôle doit contenir :
```
roles/<service>/
├── tasks/
│   ├── main.yml          # point d'entrée, importe les sous-tâches
│   ├── install.yml       # installation des paquets
│   ├── firewalld.yml     # règles firewalld
│   ├── selinux.yml       # booleans et contextes SELinux
│   └── ipa_service.yml   # principal de service FreeIPA (si applicable)
├── handlers/main.yml
├── defaults/main.yml
├── meta/main.yml
└── templates/            # fichiers .j2
```

## Gestion des secrets

- **Pattern vault** : `vars.yml` référence `{{ vault_* }}`, `vault.yml` chiffré
- **`.vault_pass`** : jamais commité (dans `.gitignore`)
- **Mots de passe** : pas de valeur placeholder dans vault.yml (hors POC)

## Questions

Ouvrez une issue avec le label `question`.
