# Rôle Ansible — Nextcloud 33 sur cloud01

**Date :** 2026-05-10
**VM cible :** cloud01.adlin.lab — 10.10.10.13 — Rocky Linux 9
**Playbook :** playbooks/03-nextcloud.yml

---

## Architecture générale

```
proxy01 (nginx)                cloud01 (Apache + PHP 8.3)
cloud.adlin.lab:443  ──HTTPS──►  cloud01.adlin.lab:443
                                      │
                               ┌──────┴──────┐
                               │  Nextcloud  │
                               │   /var/www/ │
                               │   nextcloud │
                               └──────┬──────┘
                                      │
                        ┌─────────────┼─────────────┐
                        │             │             │
                   MariaDB      /var/nc_data    FreeIPA LDAP
                   (local)      (données,        (svc_nextcloud
                                hors webroot)    → nextcloud_users)
```

**Stack :** Apache httpd + mod_ssl + PHP 8.3 (Remi) + MariaDB locale.

**TLS :** certmonger via CA FreeIPA (Dogtag) — double SAN :
- CN = `cloud01.adlin.lab` (nom interne)
- SAN = `cloud.adlin.lab` (FQDN exposé via reverse proxy)

**Données :** `/var/nc_data` — hors webroot (sécurité Nextcloud).

---

## Structure du rôle

```
roles/nextcloud/
├── defaults/main.yml
├── handlers/main.yml
├── meta/main.yml
└── tasks/
    ├── main.yml              # imports dans l'ordre, avec tags
    ├── install.yml           # Remi repo, httpd, PHP 8.3, MariaDB, certmonger, tarball NC33
    ├── ipa_service.yml       # ipaservice HTTP/cloud01.adlin.lab (delegate_to ipa01)
    ├── certmonger.yml        # ipa-getcert CN=cloud01 + SAN cloud.adlin.lab
    ├── database.yml          # MariaDB init, base nextcloud, utilisateur nextcloud
    ├── nextcloud.yml         # occ maintenance:install (guard : config.php)
    ├── ldap.yml              # occ app:enable user_ldap + occ ldap:set-config
    ├── selinux.yml           # contextes /var/nc_data, booleans httpd
    └── firewalld.yml         # 443/tcp uniquement
└── templates/
    ├── apache/nextcloud.conf.j2    # VirtualHost 443, mod_ssl, DocumentRoot
    └── php/nextcloud.ini.j2        # memory_limit, upload_max, opcache
```

**Playbook :** `playbooks/03-nextcloud.yml` — même structure que `04-mailserver.yml`.

---

## Variables (defaults/main.yml)

Préfixe `nextcloud_` sur toutes les variables du rôle.

```yaml
nextcloud_hostname:    "cloud01.adlin.lab"
nextcloud_domain:      "adlin.lab"
nextcloud_fqdn_public: "cloud.adlin.lab"
nextcloud_version:     "33.0.0"
nextcloud_tarball_url: "https://download.nextcloud.com/server/releases/nextcloud-{{ nextcloud_version }}.tar.bz2"
nextcloud_webroot:     "/var/www/nextcloud"
nextcloud_data_dir:    "/var/nc_data"

# TLS — certmonger
nextcloud_cert_path:         "/etc/pki/tls/certs/cloud01.adlin.lab.crt"
nextcloud_key_path:          "/etc/pki/tls/private/cloud01.adlin.lab.key"
nextcloud_cert_wait_retries: 30
nextcloud_cert_wait_delay:   10

# MariaDB
nextcloud_db_name:     "nextcloud"
nextcloud_db_user:     "nextcloud"
nextcloud_db_password: "{{ vault_nextcloud_db_password }}"

# Compte admin Nextcloud (premier démarrage uniquement)
nextcloud_admin_user:     "admin"
nextcloud_admin_password: "{{ vault_nextcloud_admin_password }}"

# LDAP — svc_nextcloud
nextcloud_ldap_host:       "{{ freeipa_ldap_uri }}"
nextcloud_ldap_base_dn:    "{{ freeipa_base_dn }}"
nextcloud_ldap_bind_dn:    "uid=svc_nextcloud,cn=sysaccounts,cn=etc,{{ freeipa_base_dn }}"
nextcloud_ldap_bind_pass:  "{{ ldap_bind_password_nextcloud }}"
nextcloud_ldap_user_filter: >-
  (&(objectClass=posixAccount)
  (memberOf=cn=nextcloud_users,cn=groups,cn=accounts,{{ freeipa_base_dn }}))

# Dépôt Remi PHP 8.3
nextcloud_remi_repo_url: "https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
```

**Nouvelles entrées vault requises** (à ajouter dans `vault.yml` + indirections dans `vars.yml`) :
- `vault_nextcloud_db_password` → `nextcloud_db_password`
- `vault_nextcloud_admin_password` → `nextcloud_admin_password`

Les variables LDAP (`ldap_bind_password_nextcloud`, `freeipa_ldap_uri`, `freeipa_base_dn`) existent déjà dans `group_vars/all/vars.yml` — référencées directement, sans duplication.

---

## Points techniques critiques

### Idempotence de l'installation

`occ maintenance:install` ne s'exécute qu'une fois. Guard : présence de
`/var/www/nextcloud/config/config.php` vérifiée avant l'appel (pattern identique
à `postgresql-setup --initdb` avec `args.creates` dans le rôle mailserver).

### Configuration LDAP via `occ` (ldap.yml)

Séquence idempotente :

```
occ app:enable user_ldap
# Guard : occ ldap:show-config vérifie si une config active existe déjà.
# Si oui : on réutilise le configID existant (pas de create-empty-config).
# Dans tous les cas, les ldap:set-config sont rejoués — ils sont idempotents.
occ ldap:create-empty-config          → retourne configID (s0, s1…)
occ ldap:set-config <id> ldapHost                ldaps://ipa01.adlin.lab
occ ldap:set-config <id> ldapPort                636
occ ldap:set-config <id> ldapAgentName           uid=svc_nextcloud,cn=sysaccounts,…
occ ldap:set-config <id> ldapAgentPassword       <vault>
occ ldap:set-config <id> ldapBase                dc=adlin,dc=lab
occ ldap:set-config <id> ldapUserFilter          (&(objectClass=posixAccount)(memberOf=…))
occ ldap:set-config <id> ldapUuidUserAttribute   ipaUniqueID   ← critique : évite les doublons
occ ldap:set-config <id> ldapLoginFilter         uid=%uid
occ ldap:set-config <id> ldapConfigurationActive 1
```

L'attribut `ipaUniqueID` comme UUID est le paramètre le plus critique : sans lui,
les comptes se dupliquent à chaque reconnexion FreeIPA.

### SELinux (enforcing)

| Ajustement | Raison |
|---|---|
| `/var/nc_data` → `httpd_sys_rw_content_t` | Apache doit lire/écrire les données utilisateurs |
| `httpd_can_network_connect` → true | Connexion LDAP sortante vers ipa01 (ldaps://636) |
| `httpd_can_sendmail` → true | Notifications e-mail Nextcloud |

### PHP — nextcloud.ini.j2

Valeurs imposées par Nextcloud 33 :

```ini
memory_limit = 512M
upload_max_filesize = 10G
post_max_size = 10G
max_execution_time = 3600
opcache.enable = 1
opcache.memory_consumption = 128
```

### Firewalld

Un seul port ouvert sur cloud01 : `443/tcp`. Le trafic entrant provient exclusivement
de proxy01 (réseau interne). Le port 80 n'est pas ouvert — pas de HTTP clair.

---

## Dépendances et prérequis

- FreeIPA opérationnel (`01-freeipa-server.yml` exécuté)
- cloud01 enrollé comme client IPA (`00-common.yml` exécuté sur cloud01)
- `svc_nextcloud` et groupe `nextcloud_users` créés dans FreeIPA (`01-freeipa-server.yml`)
- `vault_nextcloud_db_password` et `vault_nextcloud_admin_password` dans `vault.yml`
- Vhost `cloud.adlin.lab → cloud01:443` configuré sur proxy01 (`02-reverse-proxy.yml`)

---

## Conventions respectées

- Noms de tâches en français, préfixés par le sous-domaine (`"install | ..."`, `"ldap | ..."`)
- SELinux enforcing — aucun `setenforce 0`
- Tous les secrets via Ansible Vault (pattern `vars.yml` / `vault.yml`)
- Tags par sous-domaine : `[nextcloud, install]`, `[nextcloud, ldap]`, etc.
