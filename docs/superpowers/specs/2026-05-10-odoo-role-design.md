# Rôle Ansible — Odoo 19 Community Edition sur erp01

**Date :** 2026-05-10
**VM cible :** erp01.adlin.lab — 10.10.10.14 — Rocky Linux 9
**Playbook :** playbooks/05-odoo.yml

---

## Architecture générale

```
proxy01 (nginx)                    erp01 (Odoo 19 CE)
erp.adlin.lab:443  ──HTTP──►  erp01.adlin.lab:8069  (UI + API)
    /longpolling/  ──HTTP──►  erp01.adlin.lab:8072  (workers longpolling)

                                      │
                        ┌─────────────┼─────────────┐
                        │             │             │
                   PostgreSQL    /var/lib/odoo   FreeIPA LDAP
                   (local,       (filestore,     (svc_odoo →
                   peer auth)    addons)          odoo_users,
                                                  config manuelle UI)
```

**Pas de TLS sur erp01.** proxy01 termine le TLS et forwarde en HTTP vers 8069 (UI)
et 8072 (longpolling). Pas de certmonger, pas de principal Kerberos sur cette VM.

**Workers multi-process :** `odoo.conf` configure `workers` et `longpolling_port = 8072`.
Sans workers, le port 8072 n'existe pas et `/longpolling` échoue silencieusement.
Le reverse proxy route déjà `/longpolling → erp01:8072` (vhost erp existant dans
`roles/reverse_proxy/defaults/main.yml`).

**`proxy_mode = True`** dans `odoo.conf` est indispensable derrière proxy01 — sans
lui, Odoo ignore `X-Forwarded-Proto` et génère des URLs HTTP au lieu de HTTPS.

---

## Structure du rôle

```
roles/odoo/
├── defaults/main.yml         # toutes les variables odoo_*
├── handlers/main.yml         # Redémarrer odoo
├── meta/main.yml
└── tasks/
    ├── main.yml              # imports dans l'ordre, avec tags
    ├── install.yml           # dépôt Odoo nightly, python3.11 (EPEL), paquet odoo
    ├── database.yml          # PostgreSQL : init, rôle odoo (peer auth), base odoo
    ├── config.yml            # /etc/odoo/odoo.conf (template), démarrage service
    ├── init.yml              # odoo --init base (guard), odoo -i auth_ldap (guard)
    ├── selinux.yml           # booleans SELinux, contextes filestore
    └── firewalld.yml         # 8069/tcp + 8072/tcp
└── templates/
    └── odoo.conf.j2          # configuration Odoo complète
```

**Playbook :** `playbooks/05-odoo.yml` — même structure que `04-mailserver.yml`.

Pas de `ipa_service.yml` ni `certmonger.yml` — le TLS est géré exclusivement par proxy01.

---

## Variables (defaults/main.yml)

Préfixe `odoo_*` sur toutes les variables du rôle.

```yaml
odoo_hostname:    "erp01.adlin.lab"
odoo_fqdn_public: "erp.adlin.lab"
odoo_version:     "19.0"

# Dépôt nightly Odoo (RPM officiel)
odoo_repo_url: "https://nightly.odoo.com/{{ odoo_version }}/nightly/rpm/"

# PostgreSQL — peer authentication (pas de mot de passe)
odoo_db_name: "odoo"
odoo_db_user: "odoo"   # identique à l'utilisateur système créé par le RPM

# Workers — dimensionnement pour 2 vCPUs (erp01)
odoo_workers:          4
odoo_max_cron_threads: 2
odoo_longpolling_port: 8072

# Chemins
odoo_config_file: "/etc/odoo/odoo.conf"
odoo_log_file:    "/var/log/odoo/odoo.log"
odoo_data_dir:    "/var/lib/odoo"

# LDAP — compte de service svc_odoo
# ldap_bind_password_odoo est défini dans group_vars/all/vars.yml (indirection vault)
odoo_ldap_bind_dn:   "uid=svc_odoo,cn=sysaccounts,cn=etc,{{ freeipa_base_dn }}"
odoo_ldap_bind_pass: "{{ ldap_bind_password_odoo }}"
odoo_ldap_base:      "{{ freeipa_base_dn }}"
odoo_ldap_filter:    "(memberOf=cn=odoo_users,cn=groups,cn=accounts,{{ freeipa_base_dn }})"
```

**Aucune nouvelle entrée vault requise.** `ldap_bind_password_odoo` existe déjà dans
`vars.yml` / `vault.yml` (provisionné lors du déploiement de `freeipa_server`).

---

## Points techniques critiques

### Python 3.11 et dépendance RPM

Rocky Linux 9 AppStream = Python 3.9. Le paquet `odoo` du dépôt nightly déclare
`python3.11` comme dépendance. EPEL est déjà activé par le rôle `common` —
`python3.11` s'installe via `dnf` sans compilation. `python3-psycopg2` est également
requis (driver PostgreSQL pour les modules Ansible `community.postgresql`).

### Peer authentication PostgreSQL

Odoo se connecte à PostgreSQL via socket Unix — l'utilisateur système `odoo` (créé
par le RPM) correspond au rôle PostgreSQL `odoo`. Séquence correcte dans `database.yml` :

1. Initialiser PostgreSQL (`postgresql-setup --initdb`, guard `creates:`)
2. Démarrer et activer `postgresql`
3. Créer le rôle PostgreSQL `odoo` (`login: true`, sans mot de passe)
4. Créer la base `odoo` avec `owner: odoo`

Toutes les connexions passent par `/var/run/postgresql/.s.PGSQL.5432` — pas de TCP,
pas de mot de passe à gérer.

### Guards idempotents dans init.yml

Deux appels CLI potentiellement longs, chacun protégé par un guard distinct :

```yaml
# Guard 1 — base déjà initialisée ?
- command: psql -lqt
  register: odoo_psql_list
  become_user: odoo

- command: odoo -d odoo --init base --stop-after-init
  when: "'odoo' not in odoo_psql_list.stdout"
  become_user: odoo

# Guard 2 — auth_ldap déjà installé ?
- command: >
    psql -d odoo -tAc
    "SELECT state FROM ir_module_module WHERE name='auth_ldap'"
  register: odoo_auth_ldap_state
  become_user: odoo

- command: odoo -d odoo -i auth_ldap --stop-after-init
  when: "'installed' not in odoo_auth_ldap_state.stdout"
  become_user: odoo
```

### odoo.conf — paramètres critiques

```ini
[options]
db_host          = False       # socket Unix (pas TCP)
db_user          = odoo        # peer auth
db_name          = odoo
workers          = {{ odoo_workers }}
max_cron_threads = {{ odoo_max_cron_threads }}
longpolling_port = {{ odoo_longpolling_port }}
proxy_mode       = True        # requis derrière nginx (X-Forwarded-Proto)
data_dir         = {{ odoo_data_dir }}
logfile          = {{ odoo_log_file }}
```

### LDAP — configuration manuelle post-déploiement

Le module `auth_ldap` est activé automatiquement par `init.yml`. La configuration
du serveur LDAP (host, bind DN, filtre, base) se fait manuellement dans l'UI Odoo :

**Settings → Technical → LDAP Servers → Créer**

Valeurs à saisir :
| Champ | Valeur |
|---|---|
| LDAP Server | ldaps://ipa01.adlin.lab |
| LDAP Server port | 636 |
| LDAP binddn | `uid=svc_odoo,cn=sysaccounts,cn=etc,dc=adlin,dc=lab` |
| LDAP password | *(vault_ldap_bind_password_odoo)* |
| LDAP base | `dc=adlin,dc=lab` |
| LDAP filter | `(memberOf=cn=odoo_users,cn=groups,cn=accounts,dc=adlin,dc=lab)` |
| User TLS | cocher |

**Limitation CE :** pas de synchronisation automatique FreeIPA → rôles Odoo.
L'affectation des droits (Sales, Inventory, etc.) reste manuelle par utilisateur.

### SELinux

Le RPM Odoo inclut une policy SELinux qui tourne le processus sous le type `odoo_t`.
Ce type autorise nativement les connexions réseau sortantes (LDAP, SMTP) — le booléen
`httpd_can_network_connect` ne s'applique pas ici. La tâche `selinux.yml` se limite à :
- Vérifier que le mode enforcing est maintenu (`getenforce` dans `verify.yml`)
- Appliquer `restorecon -Rv /var/lib/odoo` si le répertoire de données a été créé
  avant l'installation du paquet (pour corriger d'éventuels mauvais contextes)

### Firewalld

Deux ports ouverts sur erp01, accessibles depuis le réseau interne (proxy01) :
- `8069/tcp` — UI Odoo + API XML-RPC/JSON-RPC
- `8072/tcp` — workers longpolling

---

## Dépendances et prérequis

- FreeIPA opérationnel (`01-freeipa-server.yml` exécuté)
- erp01 enrollé comme client IPA (`00-common.yml` exécuté sur erp01)
- `svc_odoo` et groupe `odoo_users` créés dans FreeIPA (`01-freeipa-server.yml`)
- `ldap_bind_password_odoo` dans `vault.yml` (déjà présent)
- Vhost `erp.adlin.lab → erp01:8069` + longpolling configuré sur proxy01

---

## Conventions respectées

- Noms de tâches en français, préfixés par le sous-domaine (`"install | ..."`)
- SELinux enforcing — aucun `setenforce 0`
- Secrets via Ansible Vault (indirection `vars.yml` / `vault.yml`)
- Tags par sous-domaine : `[odoo, install]`, `[odoo, database]`, etc.
