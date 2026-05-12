# ADLin — Plan de complétion du dépôt

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer les deux rôles manquants (rocketchat, freepbx), corriger les incohérences mineures du dépôt, enrichir verify.yml et finaliser la documentation pour que le projet couvre la totalité du périmètre cible décrit dans le README.

**Architecture:** Deux rôles indépendants suivent les patterns déjà établis (defaults préfixés, sous-tâches par préoccupation, SELinux enforcing). Le rôle `rocketchat` déploie RC 8.x via Docker Compose sur Rocky Linux 9 avec config LDAP FreeIPA par variables d'environnement. Le rôle `freepbx` cible Debian 12 (exception documentée) et utilise le script d'installation officiel Sangoma.

**Tech Stack:** Ansible, Rocky Linux 9, Debian 12, Docker CE + Compose, Rocket.Chat 8.x, MongoDB 7.0, FreePBX 17, Asterisk 21, FreeIPA LDAP, ufw (Debian), firewalld (Rocky)

---

## État au moment de la rédaction de ce plan

### ✅ Rôles livrés et intégrés dans site.yml (actif)
- `common`, `freeipa_server`, `reverse_proxy`, `mailserver`

### ⚠️ Rôles livrés mais commentés dans site.yml (bug à corriger — Task 1)
- `nextcloud` (rôle complet, playbook 03 prêt)
- `odoo` (rôle complet, playbook 05 prêt)

### 🚧 Rôles manquants (à créer)
- `rocketchat` — Tasks 2 à 7
- `freepbx` — Tasks 8 à 12

### 📋 Outillage à compléter
- `verify.yml` — sections par service manquantes (Task 13)
- `site.yml` — imports 06/07 à décommenter après Task 7 et 12 (Task 14)
- `README.md` — group_vars mentionnés mais absents (Task 1)

---

## Fichiers créés ou modifiés

| Fichier | Action |
|---|---|
| `playbooks/site.yml` | Modifier — décommenter 03, 05, 06, 07 |
| `inventory/production/group_vars/chat.yml` | Créer — stub group_vars |
| `inventory/production/group_vars/pbx.yml` | Créer — stub group_vars |
| `inventory/production/group_vars/all/vars.yml` | Modifier — ajouter rocketchat_admin_password |
| `requirements.yml` | Modifier — ajouter community.docker |
| `roles/rocketchat/defaults/main.yml` | Créer |
| `roles/rocketchat/handlers/main.yml` | Créer |
| `roles/rocketchat/meta/main.yml` | Créer |
| `roles/rocketchat/tasks/main.yml` | Créer |
| `roles/rocketchat/tasks/install.yml` | Créer |
| `roles/rocketchat/tasks/compose.yml` | Créer |
| `roles/rocketchat/tasks/selinux.yml` | Créer |
| `roles/rocketchat/tasks/firewalld.yml` | Créer |
| `roles/rocketchat/templates/docker-compose.yml.j2` | Créer |
| `playbooks/06-rocketchat.yml` | Créer |
| `roles/freepbx/defaults/main.yml` | Créer |
| `roles/freepbx/handlers/main.yml` | Créer |
| `roles/freepbx/meta/main.yml` | Créer |
| `roles/freepbx/tasks/main.yml` | Créer |
| `roles/freepbx/tasks/prereqs.yml` | Créer |
| `roles/freepbx/tasks/ipa_client.yml` | Créer |
| `roles/freepbx/tasks/install.yml` | Créer |
| `roles/freepbx/tasks/firewall.yml` | Créer |
| `playbooks/07-freepbx.yml` | Créer |
| `playbooks/verify.yml` | Modifier — ajouter sections nextcloud, mail, odoo, chat, pbx |

---

## Task 1 : Corrections immédiates — site.yml + group_vars

**Files:**
- Modify: `playbooks/site.yml`
- Create: `inventory/production/group_vars/chat.yml`
- Create: `inventory/production/group_vars/pbx.yml`
- Modify: `inventory/production/group_vars/all/vars.yml`

- [ ] **Step 1 : Décommenter nextcloud et odoo dans site.yml**

```yaml
# playbooks/site.yml  — remplacer les lignes commentées par :
- import_playbook: 03-nextcloud.yml
- import_playbook: 04-mailserver.yml
- import_playbook: 05-odoo.yml
```

Le fichier complet après modification :

```yaml
---
- import_playbook: 00-common.yml
- import_playbook: 01-freeipa-server.yml
- import_playbook: 02-reverse-proxy.yml
- import_playbook: 03-nextcloud.yml
- import_playbook: 04-mailserver.yml
# - import_playbook: 06-rocketchat.yml   # à décommenter après Task 7
# - import_playbook: 05-odoo.yml         # odoo déjà inclus ci-dessus
- import_playbook: 05-odoo.yml
# - import_playbook: 07-freepbx.yml      # à décommenter après Task 12
```

Note : `05-odoo.yml` était commenté mais le rôle est complet — le décommenter ici.

- [ ] **Step 2 : Créer le stub group_vars pour chat**

```yaml
# inventory/production/group_vars/chat.yml
---
# Variables spécifiques au groupe chat (chat01.adlin.lab)
# Les variables Rocket.Chat sont définies dans roles/rocketchat/defaults/main.yml
# Surcharger ici uniquement ce qui diffère des defaults du rôle.
```

- [ ] **Step 3 : Créer le stub group_vars pour pbx**

```yaml
# inventory/production/group_vars/pbx.yml
---
# Variables spécifiques au groupe pbx (pbx01.adlin.lab — Debian 12)
# Les variables FreePBX sont définies dans roles/freepbx/defaults/main.yml
# Surcharger ici uniquement ce qui diffère des defaults du rôle.
# Note : pbx01 est exclu du groupe rocky_hosts — le rôle common ne s'applique pas.
```

- [ ] **Step 4 : Ajouter rocketchat_admin_password dans vars.yml**

Ajouter à la fin de `inventory/production/group_vars/all/vars.yml` :

```yaml
rocketchat_admin_password:    "{{ vault_rocketchat_admin_password }}"
```

Et ajouter la valeur chiffrée dans vault.yml :

```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml
# Ajouter : vault_rocketchat_admin_password: "<mot_de_passe_fort>"
```

- [ ] **Step 5 : Valider le lint**

```bash
make lint
```

Résultat attendu : sortie sans erreur.

- [ ] **Step 6 : Commit**

```bash
git add playbooks/site.yml \
        inventory/production/group_vars/chat.yml \
        inventory/production/group_vars/pbx.yml \
        inventory/production/group_vars/all/vars.yml
git commit -m "fix: site.yml — décommenter nextcloud et odoo, ajouter group_vars chat et pbx"
```

---

## Task 2 : Rôle rocketchat — squelette

**Files:**
- Create: `roles/rocketchat/defaults/main.yml`
- Create: `roles/rocketchat/handlers/main.yml`
- Create: `roles/rocketchat/meta/main.yml`
- Create: `roles/rocketchat/tasks/main.yml`

- [ ] **Step 1 : Créer roles/rocketchat/defaults/main.yml**

```yaml
---
# roles/rocketchat/defaults/main.yml

rocketchat_hostname:    "chat01.adlin.lab"
rocketchat_fqdn_public: "chat.adlin.lab"
rocketchat_version:     "8"

# MongoDB — version compatible RC 8.x
rocketchat_mongo_version: "7.0"

# Répertoire de travail (volumes Docker montés ici)
rocketchat_data_dir: "/opt/rocketchat"

# Port HTTP interne — TLS terminé par proxy01
rocketchat_port: 3000

# Admin initial créé au premier démarrage
rocketchat_admin_user:  "rcadmin"
rocketchat_admin_email: "rcadmin@adlin.lab"
# rocketchat_admin_password : défini dans group_vars/all/vars.yml (référence vault)

# LDAP FreeIPA — svc_rocketchat (ldap_bind_password_rocketchat dans group_vars/all)
rocketchat_ldap_host:      "{{ ipa_server }}"
rocketchat_ldap_port:      636
rocketchat_ldap_base_dn:   "{{ freeipa_base_dn }}"
rocketchat_ldap_bind_dn:   "uid=svc_rocketchat,cn=sysaccounts,cn=etc,{{ freeipa_base_dn }}"
rocketchat_ldap_bind_pass: "{{ ldap_bind_password_rocketchat }}"
rocketchat_ldap_filter:    "(memberOf=cn=chat_users,cn=groups,cn=accounts,{{ freeipa_base_dn }})"
```

- [ ] **Step 2 : Créer roles/rocketchat/handlers/main.yml**

```yaml
---
- name: Redémarrer rocketchat
  ansible.builtin.command:
    cmd: docker compose restart rocketchat
    chdir: "{{ rocketchat_data_dir }}"
  changed_when: true
```

- [ ] **Step 3 : Créer roles/rocketchat/meta/main.yml**

```yaml
---
galaxy_info:
  role_name: rocketchat
  author: adlin
  description: "Rocket.Chat 8.x via Docker Compose avec sync LDAP FreeIPA"
  min_ansible_version: "2.14"
  platforms:
    - name: Rocky
      versions:
        - "9"
dependencies: []
```

- [ ] **Step 4 : Créer roles/rocketchat/tasks/main.yml**

```yaml
---
- name: "Rocket.Chat | Installation Docker CE"
  ansible.builtin.import_tasks: install.yml
  tags: [rocketchat, install, docker]

- name: "Rocket.Chat | Déploiement docker-compose + LDAP"
  ansible.builtin.import_tasks: compose.yml
  tags: [rocketchat, compose]

- name: "Rocket.Chat | Contextes SELinux"
  ansible.builtin.import_tasks: selinux.yml
  tags: [rocketchat, selinux]

- name: "Rocket.Chat | Règles firewalld"
  ansible.builtin.import_tasks: firewalld.yml
  tags: [rocketchat, firewalld]
```

- [ ] **Step 5 : Commit**

```bash
git add roles/rocketchat/
git commit -m "feat(rocketchat): squelette rôle — defaults, handlers, meta, tasks/main.yml"
```

---

## Task 3 : Rôle rocketchat — tasks/install.yml (Docker CE)

**Files:**
- Create: `roles/rocketchat/tasks/install.yml`
- Modify: `requirements.yml`

- [ ] **Step 1 : Écrire le test verify (vérification Docker actif)**

Ajouter à `playbooks/verify.yml` dans la section existante (ou noter pour Task 13) :
le test sera `docker info` qui retourne 0 si Docker tourne.

- [ ] **Step 2 : Créer roles/rocketchat/tasks/install.yml**

```yaml
---
# roles/rocketchat/tasks/install.yml

- name: "install | Ajouter le dépôt Docker CE"
  ansible.builtin.get_url:
    url: "https://download.docker.com/linux/centos/docker-ce.repo"
    dest: /etc/yum.repos.d/docker-ce.repo
    owner: root
    group: root
    mode: "0644"

- name: "install | Installer Docker CE, CLI et plugin Compose"
  ansible.builtin.dnf:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-compose-plugin
      - container-selinux   # policy SELinux pour les conteneurs
    state: present

- name: "install | Activer et démarrer dockerd"
  ansible.builtin.systemd:
    name: docker
    state: started
    enabled: true

- name: "install | Créer le répertoire de données"
  ansible.builtin.file:
    path: "{{ rocketchat_data_dir }}"
    state: directory
    owner: root
    group: root
    mode: "0750"
    setype: container_file_t   # contexte SELinux pour les volumes Docker
```

- [ ] **Step 3 : Ajouter community.docker à requirements.yml**

```yaml
# requirements.yml — ajouter dans la liste collections :
  - name: community.docker
```

Le fichier complet :

```yaml
---
collections:
  - name: ansible.posix
  - name: community.general
  - name: community.mysql
  - name: community.postgresql
  - name: community.docker
  - name: freeipa.ansible_freeipa
    version: ">=1.9.0"
  - name: nextcloud.admin
    version: "2.3.0"
```

- [ ] **Step 4 : Installer la nouvelle collection localement**

```bash
ansible-galaxy collection install -r requirements.yml
```

Résultat attendu : `community.docker` installée sans erreur.

- [ ] **Step 5 : Commit**

```bash
git add roles/rocketchat/tasks/install.yml requirements.yml
git commit -m "feat(rocketchat): tasks/install.yml — Docker CE + community.docker dans requirements"
```

---

## Task 4 : Rôle rocketchat — template docker-compose.yml.j2

**Files:**
- Create: `roles/rocketchat/templates/docker-compose.yml.j2`

- [ ] **Step 1 : Créer le répertoire templates**

```bash
mkdir -p roles/rocketchat/templates
```

- [ ] **Step 2 : Créer roles/rocketchat/templates/docker-compose.yml.j2**

```yaml
---
# Généré par Ansible — ne pas modifier manuellement
# roles/rocketchat/templates/docker-compose.yml.j2
services:

  mongodb:
    image: docker.io/library/mongo:{{ rocketchat_mongo_version }}
    restart: unless-stopped
    volumes:
      - ./data/db:/data/db:Z
    command: mongod --oplogSize 128 --replSet rs0
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5

  mongo-init-replica:
    image: docker.io/library/mongo:{{ rocketchat_mongo_version }}
    depends_on:
      mongodb:
        condition: service_healthy
    command: >
      mongosh --host mongodb --eval
      "rs.initiate({_id:'rs0',members:[{_id:0,host:'mongodb:27017'}]})"
    restart: on-failure

  rocketchat:
    image: registry.rocket.chat/rocketchat/rocket.chat:{{ rocketchat_version }}
    restart: unless-stopped
    volumes:
      - ./data/uploads:/app/uploads:Z
    environment:
      MONGO_URL: "mongodb://mongodb:27017/rocketchat?replicaSet=rs0"
      MONGO_OPLOG_URL: "mongodb://mongodb:27017/local?replicaSet=rs0"
      ROOT_URL: "https://{{ rocketchat_fqdn_public }}"
      PORT: "{{ rocketchat_port }}"
      # Compte admin initial (ignoré si la base existe déjà)
      ADMIN_USERNAME: "{{ rocketchat_admin_user }}"
      ADMIN_PASS: "{{ rocketchat_admin_password }}"
      ADMIN_EMAIL: "{{ rocketchat_admin_email }}"
      # LDAP FreeIPA — configuration via OVERWRITE_SETTING_ (idempotent, pris en charge dès le démarrage)
      OVERWRITE_SETTING_LDAP_Enable: "true"
      OVERWRITE_SETTING_LDAP_Host: "{{ rocketchat_ldap_host }}"
      OVERWRITE_SETTING_LDAP_Port: "{{ rocketchat_ldap_port }}"
      OVERWRITE_SETTING_LDAP_Encryption: "ssl"
      OVERWRITE_SETTING_LDAP_Reject_Unauthorized: "false"
      OVERWRITE_SETTING_LDAP_Base_DN: "{{ rocketchat_ldap_base_dn }}"
      OVERWRITE_SETTING_LDAP_Authentication: "true"
      OVERWRITE_SETTING_LDAP_Authentication_UserDN: "{{ rocketchat_ldap_bind_dn }}"
      OVERWRITE_SETTING_LDAP_Authentication_Password: "{{ rocketchat_ldap_bind_pass }}"
      OVERWRITE_SETTING_LDAP_User_Search_Filter: "{{ rocketchat_ldap_filter }}"
      OVERWRITE_SETTING_LDAP_User_Search_Scope: "sub"
      OVERWRITE_SETTING_LDAP_Username_Field: "uid"
      OVERWRITE_SETTING_LDAP_Merge_Existing_Users: "true"
      OVERWRITE_SETTING_LDAP_Sync_User_Data: "true"
      OVERWRITE_SETTING_LDAP_User_Data_FieldMap: '{"cn":"name","mail":"email"}'
      OVERWRITE_SETTING_LDAP_Background_Sync: "true"
      OVERWRITE_SETTING_LDAP_Background_Sync_Keep_Existant_Users_Updated: "true"
    depends_on:
      mongodb:
        condition: service_healthy
    ports:
      - "{{ rocketchat_port }}:{{ rocketchat_port }}"
```

- [ ] **Step 3 : Commit**

```bash
git add roles/rocketchat/templates/
git commit -m "feat(rocketchat): template docker-compose.yml.j2 avec LDAP FreeIPA"
```

---

## Task 5 : Rôle rocketchat — tasks/compose.yml (déploiement du stack)

**Files:**
- Create: `roles/rocketchat/tasks/compose.yml`

- [ ] **Step 1 : Créer roles/rocketchat/tasks/compose.yml**

```yaml
---
# roles/rocketchat/tasks/compose.yml

- name: "compose | Déployer docker-compose.yml depuis le template"
  ansible.builtin.template:
    src: docker-compose.yml.j2
    dest: "{{ rocketchat_data_dir }}/docker-compose.yml"
    owner: root
    group: root
    mode: "0640"
  notify: Redémarrer rocketchat

- name: "compose | Créer les répertoires de données persistantes"
  ansible.builtin.file:
    path: "{{ rocketchat_data_dir }}/data/{{ item }}"
    state: directory
    owner: root
    group: root
    mode: "0750"
    setype: container_file_t
  loop:
    - db
    - uploads

- name: "compose | Démarrer le stack Rocket.Chat (docker compose up)"
  ansible.builtin.command:
    cmd: docker compose up -d --remove-orphans
    chdir: "{{ rocketchat_data_dir }}"
  register: compose_up
  changed_when: "'Started' in compose_up.stdout or 'Created' in compose_up.stdout"

- name: "compose | Attendre que Rocket.Chat réponde sur le port {{ rocketchat_port }}"
  ansible.builtin.wait_for:
    host: "127.0.0.1"
    port: "{{ rocketchat_port }}"
    timeout: 120
    delay: 10
```

- [ ] **Step 2 : Commit**

```bash
git add roles/rocketchat/tasks/compose.yml
git commit -m "feat(rocketchat): tasks/compose.yml — déploiement et démarrage docker compose"
```

---

## Task 6 : Rôle rocketchat — tasks/selinux.yml + tasks/firewalld.yml

**Files:**
- Create: `roles/rocketchat/tasks/selinux.yml`
- Create: `roles/rocketchat/tasks/firewalld.yml`

- [ ] **Step 1 : Créer roles/rocketchat/tasks/selinux.yml**

```yaml
---
# roles/rocketchat/tasks/selinux.yml

- name: "selinux | Activer container_manage_cgroup (requis par Docker + systemd)"
  ansible.posix.seboolean:
    name: container_manage_cgroup
    state: true
    persistent: true

- name: "selinux | Vérifier que SELinux reste en mode enforcing"
  ansible.builtin.command: getenforce
  register: selinux_mode
  changed_when: false
  failed_when: selinux_mode.stdout != "Enforcing"
```

- [ ] **Step 2 : Créer roles/rocketchat/tasks/firewalld.yml**

```yaml
---
# roles/rocketchat/tasks/firewalld.yml
# Port 3000 restreint à l'adresse de proxy01 — pas exposé publiquement

- name: "firewalld | Ouvrir le port Rocket.Chat (3000/tcp) pour proxy01"
  ansible.posix.firewalld:
    rich_rule: "rule family='ipv4' source address='10.10.10.11' port port='3000' protocol='tcp' accept"
    permanent: true
    state: enabled
    immediate: true
```

- [ ] **Step 3 : Commit**

```bash
git add roles/rocketchat/tasks/selinux.yml roles/rocketchat/tasks/firewalld.yml
git commit -m "feat(rocketchat): tasks/selinux.yml + firewalld.yml — SELinux enforcing, port 3000 restreint à proxy01"
```

---

## Task 7 : Playbook 06-rocketchat.yml

**Files:**
- Create: `playbooks/06-rocketchat.yml`

- [ ] **Step 1 : Créer playbooks/06-rocketchat.yml**

```yaml
---
# playbooks/06-rocketchat.yml
#
# Déploie Rocket.Chat 8.x sur chat01 via Docker Compose.
# Config LDAP FreeIPA injectée par variables d'environnement (OVERWRITE_SETTING_).
#
# Prérequis obligatoires :
#   1. FreeIPA opérationnel (01-freeipa-server.yml exécuté)
#   2. chat01 enrollé comme client IPA (00-common.yml exécuté sur chat01)
#   3. svc_rocketchat et chat_users créés dans FreeIPA (01-freeipa-server.yml)
#   4. Vhost chat.adlin.lab → chat01:3000 configuré sur proxy01 (02-reverse-proxy.yml)
#
# Point de vigilance : workspace Community Rocket.Chat passe en lecture seule
# après 90 jours sans validation en ligne. Prévoir un accès internet sortant
# depuis chat01 ou accepter cette contrainte en environnement lab isolé.
#
# Utilisation :
#   ansible-playbook playbooks/06-rocketchat.yml
#   make deploy-rocketchat

- name: "Rocket.Chat 8.x — chat01"
  hosts: chat
  become: true

  roles:
    - role: rocketchat
```

- [ ] **Step 2 : Vérifier le lint du playbook et du rôle**

```bash
make lint
```

Résultat attendu : aucune erreur yamllint ni ansible-lint.

- [ ] **Step 3 : Commit**

```bash
git add playbooks/06-rocketchat.yml
git commit -m "feat(rocketchat): playbook 06-rocketchat.yml"
```

---

## Task 8 : Rôle freepbx — squelette

**Files:**
- Create: `roles/freepbx/defaults/main.yml`
- Create: `roles/freepbx/handlers/main.yml`
- Create: `roles/freepbx/meta/main.yml`
- Create: `roles/freepbx/tasks/main.yml`

- [ ] **Step 1 : Créer roles/freepbx/defaults/main.yml**

```yaml
---
# roles/freepbx/defaults/main.yml

freepbx_hostname:    "pbx01.adlin.lab"
freepbx_fqdn_public: "pbx.adlin.lab"

# Script d'installation officiel Sangoma (Debian 12)
freepbx_install_script_url: "https://github.com/FreePBX/sng_freepbx_debian_install/raw/master/sng_freepbx_debian_install.sh"
freepbx_install_script_dest: "/tmp/freepbx_install.sh"

# Sentinel d'idempotence — le script Sangoma crée ce fichier en fin d'installation
freepbx_sentinel: "/etc/asterisk/asterisk.conf"

# FreeIPA — enrollment SSH/sudo uniquement (SIP reste local)
# ipa_domain, ipa_server, ipa_realm, ipa_admin_password : définis dans group_vars/all
```

- [ ] **Step 2 : Créer roles/freepbx/handlers/main.yml**

```yaml
---
- name: Recharger asterisk
  ansible.builtin.command: asterisk -rx "core reload"
  changed_when: true

- name: Redémarrer freepbx
  ansible.builtin.service:
    name: freepbx
    state: restarted
```

- [ ] **Step 3 : Créer roles/freepbx/meta/main.yml**

```yaml
---
galaxy_info:
  role_name: freepbx
  author: adlin
  description: "FreePBX 17 + Asterisk 21 sur Debian 12, avec enrollment FreeIPA client"
  min_ansible_version: "2.14"
  platforms:
    - name: Debian
      versions:
        - bookworm
dependencies: []
```

- [ ] **Step 4 : Créer roles/freepbx/tasks/main.yml**

```yaml
---
# Note : ce rôle cible Debian 12 (pbx01). Le rôle common (Rocky Linux 9) ne
# s'applique PAS à cette VM. Toutes les préparations système sont dans ce rôle.

- name: "FreePBX | Prérequis système Debian"
  ansible.builtin.import_tasks: prereqs.yml
  tags: [freepbx, prereqs]

- name: "FreePBX | Enrollment FreeIPA client (SSH/sudo centralisés)"
  ansible.builtin.import_tasks: ipa_client.yml
  tags: [freepbx, ipa]

- name: "FreePBX | Installation FreePBX 17 + Asterisk 21"
  ansible.builtin.import_tasks: install.yml
  tags: [freepbx, install]

- name: "FreePBX | Règles pare-feu (ufw)"
  ansible.builtin.import_tasks: firewall.yml
  tags: [freepbx, firewall]
```

- [ ] **Step 5 : Commit**

```bash
git add roles/freepbx/
git commit -m "feat(freepbx): squelette rôle — defaults, handlers, meta, tasks/main.yml"
```

---

## Task 9 : Rôle freepbx — tasks/prereqs.yml + tasks/ipa_client.yml

**Files:**
- Create: `roles/freepbx/tasks/prereqs.yml`
- Create: `roles/freepbx/tasks/ipa_client.yml`

- [ ] **Step 1 : Créer roles/freepbx/tasks/prereqs.yml**

```yaml
---
# roles/freepbx/tasks/prereqs.yml
# Dépendances système Debian 12 requises avant le script Sangoma et l'enroll IPA.

- name: "prereqs | Mettre à jour le cache apt"
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600

- name: "prereqs | Installer les paquets de base"
  ansible.builtin.apt:
    name:
      - curl
      - wget
      - gnupg
      - lsb-release
      - ca-certificates
      - ufw
      - chrony             # NTP client — se synchronise sur ipa01
      - python3-ldap       # requis par community.general.ldap_entry si utilisé
    state: present

- name: "prereqs | Configurer chrony sur ipa01.adlin.lab"
  ansible.builtin.copy:
    dest: /etc/chrony/conf.d/adlin.conf
    content: |
      server {{ ipa_server }} iburst
    owner: root
    group: root
    mode: "0644"
  notify: Recharger chrony

- name: "prereqs | Activer et démarrer chrony"
  ansible.builtin.service:
    name: chrony
    state: started
    enabled: true
```

Ajouter dans `roles/freepbx/handlers/main.yml` :

```yaml
- name: Recharger chrony
  ansible.builtin.service:
    name: chrony
    state: restarted
```

Le handlers/main.yml complet :

```yaml
---
- name: Recharger asterisk
  ansible.builtin.command: asterisk -rx "core reload"
  changed_when: true

- name: Redémarrer freepbx
  ansible.builtin.service:
    name: freepbx
    state: restarted

- name: Recharger chrony
  ansible.builtin.service:
    name: chrony
    state: restarted
```

- [ ] **Step 2 : Créer roles/freepbx/tasks/ipa_client.yml**

```yaml
---
# roles/freepbx/tasks/ipa_client.yml
# Enrollment de pbx01 comme client FreeIPA sur Debian 12.
# Fournit : SSH centralisé, sudo via hbac IPA, keytab Kerberos.
# L'authentification SIP FreePBX reste locale (pas d'intégration LDAP native).

- name: "ipa_client | Installer freeipa-client (Debian)"
  ansible.builtin.apt:
    name: freeipa-client
    state: present

- name: "ipa_client | Vérifier si pbx01 est déjà enrollé"
  ansible.builtin.stat:
    path: /etc/ipa/default.conf
  register: ipa_enrolled

- name: "ipa_client | Enroller pbx01 comme client IPA"
  ansible.builtin.command: >
    ipa-client-install
      --domain {{ ipa_domain }}
      --server {{ ipa_server }}
      --realm {{ ipa_realm }}
      --principal admin
      --password {{ ipa_admin_password }}
      --mkhomedir
      --unattended
  when: not ipa_enrolled.stat.exists
  no_log: true

- name: "ipa_client | Vérifier le keytab Kerberos"
  ansible.builtin.command: klist -k /etc/krb5.keytab
  register: keytab_check
  changed_when: false
  failed_when: keytab_check.rc != 0
```

- [ ] **Step 3 : Commit**

```bash
git add roles/freepbx/tasks/prereqs.yml \
        roles/freepbx/tasks/ipa_client.yml \
        roles/freepbx/handlers/main.yml
git commit -m "feat(freepbx): prereqs Debian + enrollment IPA client"
```

---

## Task 10 : Rôle freepbx — tasks/install.yml

**Files:**
- Create: `roles/freepbx/tasks/install.yml`

- [ ] **Step 1 : Écrire le test verify (sentinel post-install)**

Le test de vérification sera ajouté dans Task 13 :
```yaml
- name: "verify | Asterisk opérationnel"
  ansible.builtin.command: asterisk -rx "core show version"
  register: asterisk_version
  changed_when: false
  failed_when: asterisk_version.rc != 0
```

- [ ] **Step 2 : Créer roles/freepbx/tasks/install.yml**

```yaml
---
# roles/freepbx/tasks/install.yml
#
# Le script Sangoma installe : PHP, MariaDB, Asterisk 21, FreePBX 17, et tous
# les modules de base. Il dure 30-60 minutes sur un serveur léger.
# Idempotence : contrôlée par la présence de {{ freepbx_sentinel }}.

- name: "install | Vérifier si FreePBX est déjà installé (idempotence)"
  ansible.builtin.stat:
    path: "{{ freepbx_sentinel }}"
  register: freepbx_installed

- name: "install | Télécharger le script d'installation Sangoma"
  ansible.builtin.get_url:
    url: "{{ freepbx_install_script_url }}"
    dest: "{{ freepbx_install_script_dest }}"
    mode: "0755"
    force: false             # ne pas re-télécharger si déjà présent
  when: not freepbx_installed.stat.exists

- name: "install | Exécuter le script Sangoma (30-60 min, async)"
  ansible.builtin.command:
    cmd: "{{ freepbx_install_script_dest }}"
  when: not freepbx_installed.stat.exists
  async: 3600
  poll: 30                   # vérifier l'avancement toutes les 30s
  register: freepbx_install_job

- name: "install | Attendre la fin de l'installation"
  ansible.builtin.async_status:
    jid: "{{ freepbx_install_job.ansible_job_id }}"
  register: freepbx_install_result
  until: freepbx_install_result.finished
  retries: 120
  delay: 30
  when: not freepbx_installed.stat.exists

- name: "install | Vérifier que le sentinel existe après installation"
  ansible.builtin.stat:
    path: "{{ freepbx_sentinel }}"
  register: freepbx_sentinel_check
  failed_when: not freepbx_sentinel_check.stat.exists

- name: "install | Activer le service FreePBX au démarrage"
  ansible.builtin.service:
    name: freepbx
    state: started
    enabled: true
```

- [ ] **Step 3 : Commit**

```bash
git add roles/freepbx/tasks/install.yml
git commit -m "feat(freepbx): tasks/install.yml — script Sangoma idempotent avec async"
```

---

## Task 11 : Rôle freepbx — tasks/firewall.yml

**Files:**
- Create: `roles/freepbx/tasks/firewall.yml`

- [ ] **Step 1 : Créer roles/freepbx/tasks/firewall.yml**

```yaml
---
# roles/freepbx/tasks/firewall.yml
# pbx01 tourne sur Debian 12 — pas de firewalld, utilisation de ufw.
#
# Ports ouverts :
#   80/tcp   — FreePBX web admin (proxifié par proxy01)
#   5060/udp — SIP (trunk entrant/sortant)
#   5061/tcp — SIP TLS
#   10000-20000/udp — RTP (flux audio)
# Source 5060/5061 : restreint à proxy01 et au trunk SIP (surcharger dans group_vars)
# Source RTP : ouvert (les endpoints SIP sont distribués — NAT/public)

- name: "firewall | Activer ufw"
  community.general.ufw:
    state: enabled
    policy: deny            # deny par défaut — whiteliste explicite

- name: "firewall | Autoriser SSH (éviter le verrouillage)"
  community.general.ufw:
    rule: allow
    port: "22"
    proto: tcp

- name: "firewall | Autoriser HTTP FreePBX admin depuis proxy01"
  community.general.ufw:
    rule: allow
    port: "80"
    proto: tcp
    src: "10.10.10.11"      # proxy01

- name: "firewall | Autoriser SIP UDP depuis proxy01"
  community.general.ufw:
    rule: allow
    port: "5060"
    proto: udp
    src: "10.10.10.11"

- name: "firewall | Autoriser SIP TLS depuis proxy01"
  community.general.ufw:
    rule: allow
    port: "5061"
    proto: tcp
    src: "10.10.10.11"

- name: "firewall | Autoriser RTP (flux audio)"
  community.general.ufw:
    rule: allow
    port: "10000:20000"
    proto: udp
```

- [ ] **Step 2 : Commit**

```bash
git add roles/freepbx/tasks/firewall.yml
git commit -m "feat(freepbx): tasks/firewall.yml — ufw SIP/RTP/HTTP"
```

---

## Task 12 : Playbook 07-freepbx.yml

**Files:**
- Create: `playbooks/07-freepbx.yml`

- [ ] **Step 1 : Créer playbooks/07-freepbx.yml**

```yaml
---
# playbooks/07-freepbx.yml
#
# Déploie FreePBX 17 + Asterisk 21 sur pbx01 (Debian 12).
#
# Prérequis obligatoires :
#   1. FreeIPA opérationnel (01-freeipa-server.yml exécuté)
#      — enrollment IPA de pbx01 effectué par ce playbook lui-même
#   2. Vhost pbx.adlin.lab → pbx01:80 configuré sur proxy01 (02-reverse-proxy.yml)
#   3. Trunk SIP configuré manuellement post-déploiement (OVH Telecom, Keyyo, etc.)
#
# Notes importantes :
#   - pbx01 cible Debian 12 (Sangoma a abandonné RHEL/Rocky Linux en 2024)
#   - Ce playbook ne s'appuie PAS sur 00-common.yml (rôle Rocky Linux uniquement)
#   - SELinux est absent de Debian — contrainte documentée et acceptée
#   - L'installation dure 30-60 min (async géré dans tasks/install.yml)
#   - L'authentification SIP reste locale dans FreePBX (pas d'intégration LDAP native)
#
# Utilisation :
#   ansible-playbook playbooks/07-freepbx.yml
#   make deploy-freepbx

- name: "FreePBX 17 + Asterisk 21 — pbx01 (Debian 12)"
  hosts: pbx
  become: true
  gather_facts: true         # requis pour ansible_distribution dans community.general.ufw

  roles:
    - role: freepbx
```

- [ ] **Step 2 : Valider le lint**

```bash
make lint
```

Résultat attendu : aucune erreur.

- [ ] **Step 3 : Commit**

```bash
git add playbooks/07-freepbx.yml
git commit -m "feat(freepbx): playbook 07-freepbx.yml — Debian 12, async 60 min"
```

---

## Task 13 : Enrichir verify.yml — sections par service

**Files:**
- Modify: `playbooks/verify.yml`

- [ ] **Step 1 : Lire le fichier verify.yml actuel**

```bash
cat playbooks/verify.yml
```

La dernière section se termine par un commentaire indiquant les sections à ajouter.

- [ ] **Step 2 : Ajouter la section Nextcloud**

Ajouter à la fin de `playbooks/verify.yml` :

```yaml
- name: "Vérification, Nextcloud"
  hosts: nextcloud
  become: true
  gather_facts: false

  tasks:
    - name: "verify | Nextcloud — occ status"
      ansible.builtin.command: >
        sudo -u apache php /var/www/html/nextcloud/occ status --output=json
      register: nc_status
      changed_when: false
      failed_when: >
        nc_status.rc != 0 or
        (nc_status.stdout | from_json).installed is not true

    - name: "verify | Apache en écoute sur 443"
      ansible.builtin.wait_for:
        host: "127.0.0.1"
        port: 443
        timeout: 10
      changed_when: false
```

- [ ] **Step 3 : Ajouter la section mailserver**

```yaml
- name: "Vérification, mailserver"
  hosts: mailservers
  become: true
  gather_facts: false

  tasks:
    - name: "verify | Postfix actif"
      ansible.builtin.systemd:
        name: postfix
        state: started
      check_mode: true
      register: postfix_check
      failed_when: postfix_check.changed

    - name: "verify | Dovecot actif"
      ansible.builtin.systemd:
        name: dovecot
        state: started
      check_mode: true
      register: dovecot_check
      failed_when: dovecot_check.changed

    - name: "verify | SOGo actif"
      ansible.builtin.systemd:
        name: sogod
        state: started
      check_mode: true
      register: sogo_check
      failed_when: sogo_check.changed

    - name: "verify | Rspamd actif"
      ansible.builtin.systemd:
        name: rspamd
        state: started
      check_mode: true
      register: rspamd_check
      failed_when: rspamd_check.changed

    - name: "verify | SMTP port 25 en écoute"
      ansible.builtin.wait_for:
        host: "127.0.0.1"
        port: 25
        timeout: 10
      changed_when: false

    - name: "verify | IMAPS port 993 en écoute"
      ansible.builtin.wait_for:
        host: "127.0.0.1"
        port: 993
        timeout: 10
      changed_when: false
```

- [ ] **Step 4 : Ajouter la section Odoo**

```yaml
- name: "Vérification, Odoo"
  hosts: odoo
  become: true
  gather_facts: false

  tasks:
    - name: "verify | Service odoo actif"
      ansible.builtin.systemd:
        name: odoo
        state: started
      check_mode: true
      register: odoo_check
      failed_when: odoo_check.changed

    - name: "verify | Page de login Odoo répond HTTP 200 sur port 8069"
      ansible.builtin.uri:
        url: "http://127.0.0.1:8069/web/login"
        status_code: 200
        timeout: 30
      changed_when: false

    - name: "verify | Port longpolling 8072 en écoute"
      ansible.builtin.wait_for:
        host: "127.0.0.1"
        port: 8072
        timeout: 10
      changed_when: false
```

- [ ] **Step 5 : Ajouter la section Rocket.Chat**

```yaml
- name: "Vérification, Rocket.Chat"
  hosts: chat
  become: true
  gather_facts: false

  tasks:
    - name: "verify | Stack Docker Compose en cours d'exécution"
      ansible.builtin.command:
        cmd: docker compose ps --status running --format json
        chdir: /opt/rocketchat
      register: compose_ps
      changed_when: false
      failed_when: >
        compose_ps.rc != 0 or
        'rocketchat' not in compose_ps.stdout

    - name: "verify | Rocket.Chat répond sur port 3000"
      ansible.builtin.wait_for:
        host: "127.0.0.1"
        port: 3000
        timeout: 30
      changed_when: false
```

- [ ] **Step 6 : Ajouter la section FreePBX**

```yaml
- name: "Vérification, FreePBX"
  hosts: pbx
  become: true
  gather_facts: false

  tasks:
    - name: "verify | Asterisk opérationnel"
      ansible.builtin.command: asterisk -rx "core show version"
      register: asterisk_version
      changed_when: false
      failed_when: asterisk_version.rc != 0

    - name: "verify | FreePBX web admin répond sur port 80"
      ansible.builtin.wait_for:
        host: "127.0.0.1"
        port: 80
        timeout: 10
      changed_when: false

    - name: "verify | Keytab Kerberos présent (enrollment IPA)"
      ansible.builtin.command: klist -k /etc/krb5.keytab
      register: keytab_pbx
      changed_when: false
      failed_when: keytab_pbx.rc != 0
```

- [ ] **Step 7 : Valider le lint**

```bash
make lint
```

Résultat attendu : aucune erreur.

- [ ] **Step 8 : Commit**

```bash
git add playbooks/verify.yml
git commit -m "feat(verify): sections nextcloud, mail, odoo, rocketchat, freepbx"
```

---

## Task 14 : Finalisation — site.yml (06/07) + README

**Files:**
- Modify: `playbooks/site.yml`
- Modify: `README.md`

- [ ] **Step 1 : Décommenter 06-rocketchat et 07-freepbx dans site.yml**

```yaml
# playbooks/site.yml — état final
---
- import_playbook: 00-common.yml
- import_playbook: 01-freeipa-server.yml
- import_playbook: 02-reverse-proxy.yml
- import_playbook: 03-nextcloud.yml
- import_playbook: 04-mailserver.yml
- import_playbook: 06-rocketchat.yml
- import_playbook: 05-odoo.yml
- import_playbook: 07-freepbx.yml
```

- [ ] **Step 2 : Mettre à jour la section "État d'avancement" du README.md**

Remplacer la section `### 🚧 À livrer` par :

```markdown
### ✅ Implémenté et fonctionnel

[... garder la liste existante ...]
- **Rôle `rocketchat`** — Rocket.Chat 8.x via Docker Compose, sync LDAP/groupes FreeIPA
- **Rôle `freepbx`** — FreePBX 17 + Asterisk 21 sur Debian 12, enrollment IPA SSH/sudo
```

Et supprimer la section `### 🚧 À livrer` (ou la laisser vide si on veut garder la structure pour de futures évolutions).

- [ ] **Step 3 : Valider le lint final**

```bash
make lint
```

Résultat attendu : aucune erreur.

- [ ] **Step 4 : Commit final**

```bash
git add playbooks/site.yml README.md
git commit -m "feat: site.yml complet, README mis à jour — tous les rôles livrés"
```

---

## Résumé de l'ordre d'exécution

```
Task 1  → corrections immédiates (5 min)
Task 2  → rocketchat squelette    (5 min)
Task 3  → rocketchat install      (10 min)
Task 4  → rocketchat template     (10 min)
Task 5  → rocketchat compose      (10 min)
Task 6  → rocketchat selinux/fw   (5 min)
Task 7  → rocketchat playbook     (5 min)
                     ↓
Task 8  → freepbx squelette       (5 min)
Task 9  → freepbx prereqs/ipa     (10 min)
Task 10 → freepbx install         (10 min)
Task 11 → freepbx firewall        (5 min)
Task 12 → freepbx playbook        (5 min)
                     ↓
Task 13 → verify.yml complet      (15 min)
Task 14 → finalisation            (10 min)
```

Durée estimée totale : **~2 heures** de développement (hors temps d'exécution des playbooks sur VMs réelles).

---

## Notes post-déploiement

### Rocket.Chat — limitation Community
Le workspace Community passe en **lecture seule après 90 jours** sans validation en ligne.  
Solution : accès internet sortant depuis `chat01`, ou accepter la contrainte pour un lab.

### FreePBX — configuration SIP manuelle
Après déploiement, configurer manuellement dans l'interface FreePBX :
1. **Trunk SIP** (OVH Telecom, Keyyo, etc.) via `Connectivity → Trunks`
2. **Extensions** via `Applications → Extensions`
3. **IVR, files d'attente** selon les besoins

### Odoo — affectation des droits manuelle
La propagation FreeIPA → rôles Odoo n'est pas automatique (limitation CE).  
Assigner les rôles dans `Settings → Users` après le premier login LDAP.
