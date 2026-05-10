# Rôle Nextcloud — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Déployer Nextcloud 33 sur cloud01.adlin.lab avec Apache + PHP 8.3 (Remi), MariaDB locale, TLS certmonger/FreeIPA, et authentification LDAP FreeIPA entièrement configurée via occ.

**Architecture:** Apache httpd + mod_ssl, PHP 8.3 via dépôt Remi (Rocky 9 AppStream = 8.1, insuffisant pour NC33). MariaDB locale. Certificat TLS double-SAN via certmonger/Dogtag. LDAP configuré via occ avec ipaUniqueID comme UUID pour éviter les doublons de comptes FreeIPA. Données hors webroot dans /var/nc_data.

**Tech Stack:** Rocky Linux 9, Apache httpd, PHP 8.3 (Remi), MariaDB 10.5, certmonger, freeipa.ansible_freeipa, community.mysql, ansible.posix, community.general.

---

## Cartographie des fichiers

**Créer :**
- `roles/nextcloud/defaults/main.yml`
- `roles/nextcloud/handlers/main.yml`
- `roles/nextcloud/meta/main.yml`
- `roles/nextcloud/tasks/main.yml`
- `roles/nextcloud/tasks/install.yml`
- `roles/nextcloud/tasks/ipa_service.yml`
- `roles/nextcloud/tasks/certmonger.yml`
- `roles/nextcloud/tasks/database.yml`
- `roles/nextcloud/tasks/nextcloud.yml`
- `roles/nextcloud/tasks/ldap.yml`
- `roles/nextcloud/tasks/selinux.yml`
- `roles/nextcloud/tasks/firewalld.yml`
- `roles/nextcloud/templates/apache/nextcloud.conf.j2`
- `roles/nextcloud/templates/php/nextcloud.ini.j2`
- `playbooks/03-nextcloud.yml`

**Modifier :**
- `ansible.cfg` — ajouter `pipelining = True` (requis pour become_user: apache)
- `inventory/production/group_vars/all/vars.yml` — indirections nextcloud_*
- `inventory/production/group_vars/all/vault.yml` — vault_nextcloud_*
- `requirements.yml` — ajouter community.mysql

---

### Task 1 : Prérequis infra (ansible.cfg + inventaire + requirements)

**Files:**
- Modify: `ansible.cfg`
- Modify: `inventory/production/group_vars/all/vars.yml`
- Modify: `inventory/production/group_vars/all/vault.yml`
- Modify: `requirements.yml`

- [ ] **Étape 1.1 : Ajouter pipelining dans ansible.cfg**

Sans `pipelining = True`, Ansible crée des fichiers temporaires que l'utilisateur
`apache` (become_user cible) ne peut pas lire — les tâches occ échouent avec
"Permission denied on temp file". Ajouter dans la section `[defaults]` :

```ini
pipelining = True
```

Le fichier complet devient :

```ini
[defaults]
inventory          = inventory/production
remote_user        = ansible
private_key_file   = ~/.ssh/adlin_ansible
host_key_checking  = False
roles_path         = roles
collections_path   = ~/.ansible/collections
interpreter_python = auto_silent
vault_password_file = .vault_pass
pipelining         = True

[privilege_escalation]
become        = True
become_method = sudo
```

- [ ] **Étape 1.2 : Ajouter community.mysql dans requirements.yml**

`community.mysql` est nécessaire pour les modules `mysql_db` et `mysql_user`.
`nextcloud.admin` est déjà présent — ne pas le modifier.

```yaml
---
collections:
  - name: ansible.posix
  - name: community.general
  - name: community.mysql
  - name: community.postgresql
  - name: freeipa.ansible_freeipa
    version: ">=1.9.0"
  - name: nextcloud.admin
    version: "2.3.0"
```

- [ ] **Étape 1.3 : Installer la collection community.mysql**

```bash
ansible-galaxy collection install community.mysql
```

Attendu : `community.mysql:X.Y.Z was installed successfully`

- [ ] **Étape 1.4 : Ajouter les indirections dans vars.yml**

Sous le bloc `# Secrets applicatifs` existant, ajouter :

```yaml
nextcloud_db_password:    "{{ vault_nextcloud_db_password }}"
nextcloud_admin_password: "{{ vault_nextcloud_admin_password }}"
```

- [ ] **Étape 1.5 : Ajouter les secrets dans vault.yml**

```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml
```

Ajouter (utiliser des mots de passe forts en production) :

```yaml
vault_nextcloud_db_password:    "ChangeMe_DB_Nextcloud_2026!"
vault_nextcloud_admin_password: "ChangeMe_Admin_Nextcloud_2026!"
```

- [ ] **Étape 1.6 : Vérifier**

```bash
ansible-vault view inventory/production/group_vars/all/vault.yml | grep vault_nextcloud
```

Attendu : les deux entrées `vault_nextcloud_*` apparaissent.

- [ ] **Étape 1.7 : Commit**

```bash
git add ansible.cfg requirements.yml \
        inventory/production/group_vars/all/vars.yml \
        inventory/production/group_vars/all/vault.yml
git commit -m "feat(nextcloud): prérequis infra — pipelining, community.mysql, vars vault"
```

---

### Task 2 : Scaffolding du rôle (meta + handlers + defaults)

**Files:**
- Create: `roles/nextcloud/meta/main.yml`
- Create: `roles/nextcloud/handlers/main.yml`
- Create: `roles/nextcloud/defaults/main.yml`

- [ ] **Étape 2.1 : Créer la structure de dossiers**

```bash
mkdir -p roles/nextcloud/{defaults,handlers,meta,tasks,templates/apache,templates/php}
```

- [ ] **Étape 2.2 : Créer roles/nextcloud/meta/main.yml**

```yaml
---
galaxy_info:
  role_name: nextcloud
  author: fred
  description: "Déploie Nextcloud 33 sur Rocky Linux 9 avec FreeIPA LDAP et certmonger TLS"
  min_ansible_version: "2.14"
  platforms:
    - name: Rocky
      versions:
        - "9"
dependencies: []
```

- [ ] **Étape 2.3 : Créer roles/nextcloud/handlers/main.yml**

```yaml
---
- name: Redémarrer httpd
  ansible.builtin.systemd:
    name: httpd
    state: restarted

- name: Recharger httpd
  ansible.builtin.systemd:
    name: httpd
    state: reloaded
```

- [ ] **Étape 2.4 : Créer roles/nextcloud/defaults/main.yml**

```yaml
---
# roles/nextcloud/defaults/main.yml

nextcloud_hostname:    "cloud01.adlin.lab"
nextcloud_domain:      "adlin.lab"
nextcloud_fqdn_public: "cloud.adlin.lab"
nextcloud_version:     "33.0.0"
nextcloud_tarball_url: "https://download.nextcloud.com/server/releases/nextcloud-{{ nextcloud_version }}.tar.bz2"
nextcloud_webroot:     "/var/www/nextcloud"
nextcloud_data_dir:    "/var/nc_data"

# TLS — certmonger via CA FreeIPA (Dogtag)
nextcloud_cert_path:         "/etc/pki/tls/certs/cloud01.adlin.lab.crt"
nextcloud_key_path:          "/etc/pki/tls/private/cloud01.adlin.lab.key"
nextcloud_cert_wait_retries: 30
nextcloud_cert_wait_delay:   10

# MariaDB
nextcloud_db_name:     "nextcloud"
nextcloud_db_user:     "nextcloud"
nextcloud_db_password: "{{ vault_nextcloud_db_password }}"

# Compte admin Nextcloud (utilisé une seule fois par occ maintenance:install)
nextcloud_admin_user:     "ncadmin"
nextcloud_admin_password: "{{ vault_nextcloud_admin_password }}"

# LDAP — svc_nextcloud (indirections définies dans group_vars/all/vars.yml)
nextcloud_ldap_host:       "{{ freeipa_ldap_uri }}"
nextcloud_ldap_base_dn:    "{{ freeipa_base_dn }}"
nextcloud_ldap_bind_dn:    "uid=svc_nextcloud,cn=sysaccounts,cn=etc,{{ freeipa_base_dn }}"
nextcloud_ldap_bind_pass:  "{{ ldap_bind_password_nextcloud }}"
nextcloud_ldap_user_filter: >-
  (&(objectClass=posixAccount)(memberOf=cn=nextcloud_users,cn=groups,cn=accounts,{{ freeipa_base_dn }}))
# configID attribué par Nextcloud à la première config LDAP créée via occ
nextcloud_ldap_config_id:  "s0"

# Dépôt Remi PHP 8.3
nextcloud_remi_repo_url: "https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
```

- [ ] **Étape 2.5 : Créer un stub tasks/main.yml (sera remplacé dans Task 13)**

```yaml
---
# Stub — complété dans la Task 13
```

- [ ] **Étape 2.6 : Commit**

```bash
git add roles/nextcloud/
git commit -m "feat(nextcloud): scaffolding rôle (meta, handlers, defaults)"
```

---

### Task 3 : Playbook 03-nextcloud.yml

**Files:**
- Create: `playbooks/03-nextcloud.yml`

- [ ] **Étape 3.1 : Créer playbooks/03-nextcloud.yml**

```yaml
---
# playbooks/03-nextcloud.yml
#
# Déploie Nextcloud 33 sur cloud01 : Apache + PHP 8.3 (Remi) + MariaDB + LDAP FreeIPA.
#
# Prérequis obligatoires :
#   1. FreeIPA opérationnel (01-freeipa-server.yml exécuté)
#   2. cloud01 enrollé comme client IPA (00-common.yml exécuté sur cloud01)
#   3. svc_nextcloud et nextcloud_users créés dans FreeIPA (01-freeipa-server.yml)
#   4. vault_nextcloud_db_password et vault_nextcloud_admin_password dans vault.yml
#   5. Vhost cloud.adlin.lab → cloud01:443 configuré sur proxy01 (02-reverse-proxy.yml)
#
# Utilisation :
#   ansible-playbook playbooks/03-nextcloud.yml
#   ansible-playbook playbooks/03-nextcloud.yml --tags install
#   ansible-playbook playbooks/03-nextcloud.yml --tags ldap

- name: "Nextcloud 33 — cloud01"
  hosts: nextcloud
  become: true

  roles:
    - role: nextcloud
```

- [ ] **Étape 3.2 : Commit**

```bash
git add playbooks/03-nextcloud.yml
git commit -m "feat(nextcloud): playbook 03-nextcloud.yml"
```

---

### Task 4 : tasks/install.yml

**Files:**
- Create: `roles/nextcloud/tasks/install.yml`

- [ ] **Étape 4.1 : Créer roles/nextcloud/tasks/install.yml**

```yaml
---
# roles/nextcloud/tasks/install.yml
#
# Rocky 9 AppStream = PHP 8.1. Nextcloud 33 exige PHP ≥ 8.2.
# Remi est le dépôt de référence pour PHP récent sur RHEL/Rocky.

- name: "install | Installer le dépôt Remi"
  ansible.builtin.dnf:
    name: "{{ nextcloud_remi_repo_url }}"
    state: present

- name: "install | Activer le module PHP 8.3 (Remi)"
  ansible.builtin.command:
    cmd: dnf module enable php:remi-8.3 -y
  changed_when: false

- name: "install | Installer Apache, PHP 8.3 et modules Nextcloud"
  ansible.builtin.dnf:
    name:
      - httpd
      - mod_ssl
      - php
      - php-gd
      - php-mbstring
      - php-intl
      - php-xml
      - php-zip
      - php-curl
      - php-ldap
      - php-mysqlnd
      - php-opcache
      - php-bcmath
      - php-gmp
      - php-imagick
      - bzip2
      - certmonger
      - mariadb-server
      - python3-PyMySQL
    state: present

- name: "install | Démarrer et activer httpd"
  ansible.builtin.systemd:
    name: httpd
    state: started
    enabled: true

- name: "install | Démarrer et activer MariaDB"
  ansible.builtin.systemd:
    name: mariadb
    state: started
    enabled: true

- name: "install | Démarrer et activer certmonger"
  ansible.builtin.systemd:
    name: certmonger
    state: started
    enabled: true

- name: "install | Télécharger le checksum sha256 de Nextcloud {{ nextcloud_version }}"
  ansible.builtin.get_url:
    url: "{{ nextcloud_tarball_url }}.sha256"
    dest: "/tmp/nextcloud-{{ nextcloud_version }}.tar.bz2.sha256"
    mode: "0644"

- name: "install | Lire le checksum sha256"
  ansible.builtin.slurp:
    src: "/tmp/nextcloud-{{ nextcloud_version }}.tar.bz2.sha256"
  register: nextcloud_sha256_raw

- name: "install | Télécharger le tarball Nextcloud {{ nextcloud_version }}"
  ansible.builtin.get_url:
    url: "{{ nextcloud_tarball_url }}"
    dest: "/tmp/nextcloud-{{ nextcloud_version }}.tar.bz2"
    checksum: "sha256:{{ (nextcloud_sha256_raw.content | b64decode).split()[0] }}"
    mode: "0644"

- name: "install | Extraire le tarball Nextcloud dans /var/www/"
  ansible.builtin.unarchive:
    src: "/tmp/nextcloud-{{ nextcloud_version }}.tar.bz2"
    dest: /var/www/
    remote_src: true
    owner: apache
    group: apache
    creates: "{{ nextcloud_webroot }}/occ"

- name: "install | Créer le répertoire de données (hors webroot)"
  ansible.builtin.file:
    path: "{{ nextcloud_data_dir }}"
    state: directory
    owner: apache
    group: apache
    mode: "0750"
```

- [ ] **Étape 4.2 : Commit**

```bash
git add roles/nextcloud/tasks/install.yml
git commit -m "feat(nextcloud): install.yml — Remi PHP 8.3, Apache, MariaDB, tarball NC33"
```

---

### Task 5 : tasks/ipa_service.yml

**Files:**
- Create: `roles/nextcloud/tasks/ipa_service.yml`

- [ ] **Étape 5.1 : Créer roles/nextcloud/tasks/ipa_service.yml**

```yaml
---
# roles/nextcloud/tasks/ipa_service.yml
#
# Crée le principal HTTP/cloud01.adlin.lab dans FreeIPA.
# Requis pour que certmonger puisse demander et renouveler le certificat TLS Apache.

- name: "ipa_service | Créer le principal HTTP pour cloud01"
  freeipa.ansible_freeipa.ipaservice:
    ipaadmin_password: "{{ ipa_admin_password }}"
    name: "HTTP/{{ nextcloud_hostname }}"
    state: present
  delegate_to: ipa01.adlin.lab
```

- [ ] **Étape 5.2 : Commit**

```bash
git add roles/nextcloud/tasks/ipa_service.yml
git commit -m "feat(nextcloud): ipa_service.yml — principal Kerberos HTTP/cloud01"
```

---

### Task 6 : tasks/certmonger.yml

**Files:**
- Create: `roles/nextcloud/tasks/certmonger.yml`

- [ ] **Étape 6.1 : Créer roles/nextcloud/tasks/certmonger.yml**

```yaml
---
# roles/nextcloud/tasks/certmonger.yml
#
# Demande un certificat TLS double-SAN via certmonger et la CA FreeIPA (Dogtag).
#   CN  = cloud01.adlin.lab  (nom interne de la VM)
#   SAN = cloud.adlin.lab    (FQDN exposé aux clients via reverse proxy)

- name: "certmonger | Vérifier les certificats déjà suivis"
  ansible.builtin.command: getcert list
  register: nextcloud_getcert_list
  changed_when: false

- name: "certmonger | Demander le certificat TLS à FreeIPA CA"
  ansible.builtin.shell: >
    ipa-getcert request
    -f {{ nextcloud_cert_path }}
    -k {{ nextcloud_key_path }}
    -K HTTP/{{ nextcloud_hostname }}@{{ ipa_realm }}
    -N "CN={{ nextcloud_hostname }}"
    -D {{ nextcloud_hostname }}
    -D {{ nextcloud_fqdn_public }}
  when: nextcloud_cert_path not in nextcloud_getcert_list.stdout
  changed_when: true

- name: "certmonger | Attendre la délivrance du certificat par Dogtag"
  ansible.builtin.command: getcert list -f {{ nextcloud_cert_path }}
  register: nextcloud_cert_status
  until: "'status: MONITORING' in nextcloud_cert_status.stdout"
  retries: "{{ nextcloud_cert_wait_retries }}"
  delay: "{{ nextcloud_cert_wait_delay }}"
  changed_when: false

- name: "certmonger | Afficher l'état du certificat"
  ansible.builtin.debug:
    msg: "{{ nextcloud_cert_status.stdout_lines }}"
```

- [ ] **Étape 6.2 : Commit**

```bash
git add roles/nextcloud/tasks/certmonger.yml
git commit -m "feat(nextcloud): certmonger.yml — TLS double-SAN via FreeIPA CA"
```

---

### Task 7 : tasks/database.yml

**Files:**
- Create: `roles/nextcloud/tasks/database.yml`

- [ ] **Étape 7.1 : Créer roles/nextcloud/tasks/database.yml**

```yaml
---
# roles/nextcloud/tasks/database.yml
#
# MariaDB est installé et démarré dans install.yml.
# Cette tâche provisionne uniquement la base et l'utilisateur Nextcloud.
# login_unix_socket : connexion sans mot de passe root (auth socket par défaut).

- name: "database | Créer la base de données nextcloud (utf8mb4)"
  community.mysql.mysql_db:
    name: "{{ nextcloud_db_name }}"
    encoding: utf8mb4
    collation: utf8mb4_general_ci
    state: present
    login_unix_socket: /var/lib/mysql/mysql.sock

- name: "database | Créer l'utilisateur nextcloud"
  community.mysql.mysql_user:
    name: "{{ nextcloud_db_user }}"
    password: "{{ nextcloud_db_password }}"
    priv: "{{ nextcloud_db_name }}.*:ALL"
    host: localhost
    state: present
    login_unix_socket: /var/lib/mysql/mysql.sock
  no_log: true
```

- [ ] **Étape 7.2 : Commit**

```bash
git add roles/nextcloud/tasks/database.yml
git commit -m "feat(nextcloud): database.yml — base MariaDB nextcloud + utilisateur"
```

---

### Task 8 : Template Apache

**Files:**
- Create: `roles/nextcloud/templates/apache/nextcloud.conf.j2`

- [ ] **Étape 8.1 : Créer roles/nextcloud/templates/apache/nextcloud.conf.j2**

```jinja2
# {{ ansible_managed }}
# VirtualHost Nextcloud — cloud01.adlin.lab
# HTTPS uniquement : le port 80 est géré par proxy01 (redirection → HTTPS)

<VirtualHost *:443>
    ServerName  {{ nextcloud_fqdn_public }}
    ServerAlias {{ nextcloud_hostname }}
    DocumentRoot {{ nextcloud_webroot }}

    SSLEngine on
    SSLCertificateFile    {{ nextcloud_cert_path }}
    SSLCertificateKeyFile {{ nextcloud_key_path }}

    <Directory {{ nextcloud_webroot }}>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
    </Directory>

    <IfModule mod_headers.c>
        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
    </IfModule>

    ErrorLog  /var/log/httpd/nextcloud_error.log
    CustomLog /var/log/httpd/nextcloud_access.log combined
</VirtualHost>
```

- [ ] **Étape 8.2 : Commit**

```bash
git add roles/nextcloud/templates/apache/nextcloud.conf.j2
git commit -m "feat(nextcloud): template VirtualHost Apache HTTPS"
```

---

### Task 9 : Template PHP

**Files:**
- Create: `roles/nextcloud/templates/php/nextcloud.ini.j2`

- [ ] **Étape 9.1 : Créer roles/nextcloud/templates/php/nextcloud.ini.j2**

```jinja2
; {{ ansible_managed }}
; Paramètres PHP requis par Nextcloud 33
; Déployé dans /etc/php.d/40-nextcloud.ini

memory_limit        = 512M
upload_max_filesize = 10G
post_max_size       = 10G
max_execution_time  = 3600
max_input_time      = 3600

; OPcache
opcache.enable                  = 1
opcache.interned_strings_buffer = 32
opcache.max_accelerated_files   = 10000
opcache.memory_consumption      = 128
opcache.save_comments           = 1
opcache.revalidate_freq         = 1
```

- [ ] **Étape 9.2 : Commit**

```bash
git add roles/nextcloud/templates/php/nextcloud.ini.j2
git commit -m "feat(nextcloud): template PHP nextcloud.ini (memory, upload, opcache)"
```

---

### Task 10 : tasks/nextcloud.yml

**Files:**
- Create: `roles/nextcloud/tasks/nextcloud.yml`

- [ ] **Étape 10.1 : Créer roles/nextcloud/tasks/nextcloud.yml**

```yaml
---
# roles/nextcloud/tasks/nextcloud.yml
#
# Déploie la config Apache + PHP, puis lance occ maintenance:install.
# Guard : config.php est créé par occ maintenance:install — présent = déjà installé.
# Les appels config:system:set (trusted_domains) sont idempotents nativement.

- name: "nextcloud | Déployer la configuration Apache"
  ansible.builtin.template:
    src: apache/nextcloud.conf.j2
    dest: /etc/httpd/conf.d/nextcloud.conf
    owner: root
    group: root
    mode: "0644"
  notify: Recharger httpd

- name: "nextcloud | Déployer la configuration PHP"
  ansible.builtin.template:
    src: php/nextcloud.ini.j2
    dest: /etc/php.d/40-nextcloud.ini
    owner: root
    group: root
    mode: "0644"
  notify: Redémarrer httpd

- name: "nextcloud | Vérifier si Nextcloud est déjà installé"
  ansible.builtin.stat:
    path: "{{ nextcloud_webroot }}/config/config.php"
  register: nextcloud_config_php

- name: "nextcloud | Lancer occ maintenance:install"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ maintenance:install
      --database=mysql
      --database-host=localhost
      --database-name={{ nextcloud_db_name }}
      --database-user={{ nextcloud_db_user }}
      --database-pass={{ nextcloud_db_password }}
      --admin-user={{ nextcloud_admin_user }}
      --admin-pass={{ nextcloud_admin_password }}
      --data-dir={{ nextcloud_data_dir }}
  become_user: apache
  when: not nextcloud_config_php.stat.exists
  changed_when: true
  no_log: true

- name: "nextcloud | Configurer trusted_domain public ({{ nextcloud_fqdn_public }})"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ config:system:set
      trusted_domains 0 --value={{ nextcloud_fqdn_public }}
  become_user: apache
  changed_when: false

- name: "nextcloud | Configurer trusted_domain interne ({{ nextcloud_hostname }})"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ config:system:set
      trusted_domains 1 --value={{ nextcloud_hostname }}
  become_user: apache
  changed_when: false
```

- [ ] **Étape 10.2 : Commit**

```bash
git add roles/nextcloud/tasks/nextcloud.yml
git commit -m "feat(nextcloud): nextcloud.yml — config Apache/PHP + occ install + trusted_domains"
```

---

### Task 11 : tasks/ldap.yml

**Files:**
- Create: `roles/nextcloud/tasks/ldap.yml`

- [ ] **Étape 11.1 : Créer roles/nextcloud/tasks/ldap.yml**

```yaml
---
# roles/nextcloud/tasks/ldap.yml
#
# Configure l'authentification LDAP FreeIPA via occ.
#
# ipaUniqueID comme attribut UUID : valeur stable assignée par FreeIPA à chaque
# entrée, contrairement à entryUUID qui peut changer. Sans cet attribut, Nextcloud
# duplique les comptes utilisateurs à chaque reconnexion LDAP.
#
# Guard idempotent : si une config LDAP active existe déjà (ldap:show-config
# retourne 'configID'), on réutilise nextcloud_ldap_config_id (défaut: s0).
# Les ldap:set-config sont idempotents — sûrs à rejouer.

- name: "ldap | Activer l'application user_ldap"
  ansible.builtin.command:
    cmd: php {{ nextcloud_webroot }}/occ app:enable user_ldap
  become_user: apache
  changed_when: false

- name: "ldap | Vérifier si une config LDAP existe"
  ansible.builtin.command:
    cmd: php {{ nextcloud_webroot }}/occ ldap:show-config
  become_user: apache
  register: nextcloud_ldap_show
  changed_when: false

- name: "ldap | Créer une config LDAP vide si nécessaire"
  ansible.builtin.command:
    cmd: php {{ nextcloud_webroot }}/occ ldap:create-empty-config
  become_user: apache
  when: "'configID' not in nextcloud_ldap_show.stdout"
  changed_when: true

- name: "ldap | Serveur LDAP (host)"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ ldap:set-config
      {{ nextcloud_ldap_config_id }} ldapHost {{ nextcloud_ldap_host }}
  become_user: apache
  changed_when: false

- name: "ldap | Port LDAP (636 — LDAPS)"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ ldap:set-config
      {{ nextcloud_ldap_config_id }} ldapPort 636
  become_user: apache
  changed_when: false

- name: "ldap | DN du compte de service"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ ldap:set-config
      {{ nextcloud_ldap_config_id }} ldapAgentName "{{ nextcloud_ldap_bind_dn }}"
  become_user: apache
  changed_when: false

- name: "ldap | Mot de passe du compte de service"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ ldap:set-config
      {{ nextcloud_ldap_config_id }} ldapAgentPassword "{{ nextcloud_ldap_bind_pass }}"
  become_user: apache
  changed_when: false
  no_log: true

- name: "ldap | Base DN"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ ldap:set-config
      {{ nextcloud_ldap_config_id }} ldapBase "{{ nextcloud_ldap_base_dn }}"
  become_user: apache
  changed_when: false

- name: "ldap | Filtre utilisateurs (groupe nextcloud_users)"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ ldap:set-config
      {{ nextcloud_ldap_config_id }} ldapUserFilter "{{ nextcloud_ldap_user_filter }}"
  become_user: apache
  changed_when: false

- name: "ldap | Attribut UUID → ipaUniqueID (évite les doublons de comptes)"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ ldap:set-config
      {{ nextcloud_ldap_config_id }} ldapUuidUserAttribute ipaUniqueID
  become_user: apache
  changed_when: false

- name: "ldap | Filtre de connexion (login = uid)"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ ldap:set-config
      {{ nextcloud_ldap_config_id }} ldapLoginFilter "uid=%uid"
  become_user: apache
  changed_when: false

- name: "ldap | Activer la configuration LDAP"
  ansible.builtin.command:
    cmd: >
      php {{ nextcloud_webroot }}/occ ldap:set-config
      {{ nextcloud_ldap_config_id }} ldapConfigurationActive 1
  become_user: apache
  changed_when: false
```

- [ ] **Étape 11.2 : Commit**

```bash
git add roles/nextcloud/tasks/ldap.yml
git commit -m "feat(nextcloud): ldap.yml — occ user_ldap FreeIPA (ipaUniqueID comme UUID)"
```

---

### Task 12 : tasks/selinux.yml

**Files:**
- Create: `roles/nextcloud/tasks/selinux.yml`

- [ ] **Étape 12.1 : Créer roles/nextcloud/tasks/selinux.yml**

```yaml
---
# roles/nextcloud/tasks/selinux.yml
#
# httpd_can_network_connect : connexion LDAP sortante vers ipa01 (ldaps://636)
# httpd_can_sendmail        : notifications e-mail Nextcloud
# httpd_sys_rw_content_t   : Apache lit et écrit les fichiers dans /var/nc_data

- name: "selinux | Appliquer le contexte httpd_sys_rw_content_t sur /var/nc_data"
  community.general.sefcontext:
    target: "{{ nextcloud_data_dir }}(/.*)?"
    setype: httpd_sys_rw_content_t
    state: present
  register: nextcloud_sefcontext_data

- name: "selinux | Restaurer les contextes SELinux sur /var/nc_data"
  ansible.builtin.command: "restorecon -Rv {{ nextcloud_data_dir }}"
  when: nextcloud_sefcontext_data.changed
  changed_when: true

- name: "selinux | Autoriser httpd à initier des connexions réseau (LDAP vers ipa01)"
  ansible.posix.seboolean:
    name: httpd_can_network_connect
    state: true
    persistent: true

- name: "selinux | Autoriser httpd à envoyer des e-mails (notifications Nextcloud)"
  ansible.posix.seboolean:
    name: httpd_can_sendmail
    state: true
    persistent: true
```

- [ ] **Étape 12.2 : Commit**

```bash
git add roles/nextcloud/tasks/selinux.yml
git commit -m "feat(nextcloud): selinux.yml — contexte nc_data + booleans httpd"
```

---

### Task 13 : tasks/firewalld.yml

**Files:**
- Create: `roles/nextcloud/tasks/firewalld.yml`

- [ ] **Étape 13.1 : Créer roles/nextcloud/tasks/firewalld.yml**

```yaml
---
# Seul 443/tcp est ouvert sur cloud01.
# Le trafic entrant provient exclusivement de proxy01 (réseau interne).
# Le port 80 n'est pas ouvert : aucun HTTP clair sur cloud01.

- name: "firewalld | Autoriser HTTPS (443/tcp)"
  ansible.posix.firewalld:
    service: https
    permanent: true
    state: enabled
    immediate: true
```

- [ ] **Étape 13.2 : Commit**

```bash
git add roles/nextcloud/tasks/firewalld.yml
git commit -m "feat(nextcloud): firewalld.yml — HTTPS uniquement (443/tcp)"
```

---

### Task 14 : tasks/main.yml — Orchestration et vérification syntaxe

**Files:**
- Modify: `roles/nextcloud/tasks/main.yml`

- [ ] **Étape 14.1 : Écrire roles/nextcloud/tasks/main.yml**

```yaml
---
- name: "Nextcloud | Installation dépôts, paquets et tarball"
  ansible.builtin.import_tasks: install.yml
  tags: [nextcloud, install]

- name: "Nextcloud | Principal Kerberos HTTP dans FreeIPA"
  ansible.builtin.import_tasks: ipa_service.yml
  tags: [nextcloud, freeipa, ipa, pki]

- name: "Nextcloud | Certificat TLS via certmonger"
  ansible.builtin.import_tasks: certmonger.yml
  tags: [nextcloud, certmonger, tls, pki]

- name: "Nextcloud | Base de données MariaDB"
  ansible.builtin.import_tasks: database.yml
  tags: [nextcloud, database, mariadb]

- name: "Nextcloud | Configuration Apache + PHP + installation occ"
  ansible.builtin.import_tasks: nextcloud.yml
  tags: [nextcloud, config, occ]

- name: "Nextcloud | Configuration LDAP FreeIPA (user_ldap)"
  ansible.builtin.import_tasks: ldap.yml
  tags: [nextcloud, ldap, freeipa]

- name: "Nextcloud | Contextes SELinux"
  ansible.builtin.import_tasks: selinux.yml
  tags: [nextcloud, selinux]

- name: "Nextcloud | Règles firewalld"
  ansible.builtin.import_tasks: firewalld.yml
  tags: [nextcloud, firewalld]
```

- [ ] **Étape 14.2 : Vérification syntaxe complète**

```bash
ansible-playbook playbooks/03-nextcloud.yml --syntax-check
```

Attendu : `playbook: playbooks/03-nextcloud.yml` sans erreur ni warning.

- [ ] **Étape 14.3 : Commit final**

```bash
git add roles/nextcloud/tasks/main.yml
git commit -m "feat(nextcloud): tasks/main.yml — orchestration complète, syntaxe validée"
```

---

## Self-review

**Couverture spec :**
- ✅ Apache httpd + mod_ssl + PHP 8.3 (Remi) → Tasks 4, 8, 9, 10
- ✅ MariaDB locale (utf8mb4) → Tasks 4, 7
- ✅ certmonger double-SAN (cloud01 + cloud.adlin.lab) → Tasks 5, 6
- ✅ occ maintenance:install avec guard config.php → Task 10
- ✅ trusted_domains (public + interne) → Task 10
- ✅ occ ldap:set-config + ipaUniqueID → Task 11
- ✅ SELinux enforcing (contextes + booleans) → Task 12
- ✅ Firewalld 443/tcp uniquement → Task 13
- ✅ Variables vault (db + admin) → Task 1
- ✅ pipelining (requis pour become_user: apache) → Task 1
- ✅ community.mysql → Task 1
- ✅ Playbook 03-nextcloud.yml → Task 3
- ✅ Conventions françaises + tags par sous-domaine → Task 14

**Cohérence des types :**
- `nextcloud_ldap_config_id: "s0"` défini dans defaults (Task 2), utilisé dans ldap.yml (Task 11) ✅
- `nextcloud_config_php.stat.exists` enregistré et consommé dans nextcloud.yml (Task 10) ✅
- `nextcloud_ldap_show.stdout` enregistré et consommé dans ldap.yml (Task 11) ✅
- `nextcloud_getcert_list.stdout` enregistré et consommé dans certmonger.yml (Task 6) ✅
- `nextcloud_sha256_raw.content` enregistré et consommé dans install.yml (Task 4) ✅

**Aucun placeholder :** pas de TBD, TODO, ou "à compléter" dans le plan.
