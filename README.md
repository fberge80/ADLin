# ADLin — Infrastructure PME open-source sur Proxmox VE

> Remplacement complet d'une stack Microsoft 365 / Google Workspace / Salesforce
> par des équivalents open-source auto-hébergés, déployés intégralement via Ansible
> sur Rocky Linux 9 avec FreeIPA comme socle d'identité centralisé.

![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat-square&logo=ansible&logoColor=white)
![Rocky Linux](https://img.shields.io/badge/Rocky_Linux_9-10B981?style=flat-square&logo=rockylinux&logoColor=white)
![FreeIPA](https://img.shields.io/badge/FreeIPA-IdM-blue?style=flat-square)
![SELinux](https://img.shields.io/badge/SELinux-enforcing-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## Objectif

Ce projet démontre le déploiement automatisé d'une infrastructure IT complète
pour une PME de 10 à 200 salariés, avec :

- **Zéro licence logicielle** — contre $12–50/utilisateur/mois pour une stack
  Microsoft 365 + Salesforce + Zoom équivalente
- **SELinux en mode enforcing** sur toutes les VM Rocky Linux 9 — là où la
  plupart des guides recommandent de le désactiver
- **FreeIPA comme annuaire central** (LDAP + Kerberos + PKI + DNS) pour tous
  les services sans exception
- **Ansible exclusivement** : rôles structurés, idempotents, commentés, secrets
  chiffrés avec Vault

---
## État d'avancement

> Ce dépôt est en construction active. La section ci-dessous précise ce qui
> est implémenté et fonctionnel à date, et ce qui reste à livrer. L'architecture
> décrite plus loin représente le périmètre cible final du projet.

### ✅ Implémenté et fonctionnel

- **Rôle `common`** — hardening Rocky Linux 9 : SELinux enforcing, EPEL/CRB,
  paquets de base, chrony (client ou serveur NTP), enrollment FreeIPA client,
  firewalld
- **Rôle `freeipa_server`** — déploiement FreeIPA Server complet : DNS intégré,
  PKI Dogtag, KRA (Key Recovery Authority), comptes de service LDAP en
  `cn=sysaccounts`, groupes applicatifs POSIX, règles firewalld
- **Rôle `reverse_proxy`** — Nginx avec TLS automatisé via certmonger et la CA
  FreeIPA : principal de service Kerberos, certificat multi-SAN, SELinux booleans,
  vhosts templatés (support Odoo longpolling), HSTS et en-têtes de sécurité
- **Rôle `mailserver`** — stack mail complète avec authentification FreeIPA LDAP :
  - Postfix : MTA, boîtes virtuelles LDAP, livraison LMTP → Dovecot, submission
    SASL/STARTTLS (587), filtre antispam via milter Rspamd
  - Dovecot : IMAPS (993), `auth_bind` FreeIPA (le mot de passe n'est jamais
    exposé dans l'annuaire), stockage Maildir virtuel, ManageSieve (4190)
  - Rspamd : filtre antispam milter, cache Redis (bayes, rate limiting)
  - SOGo : webmail + CalDAV + CardDAV + ActiveSync, base PostgreSQL, frontend
    nginx local (proxy01 → mail01:80 → sogod:20000)
  - certmonger : certificat multi-SAN (`mail01.adlin.lab` + `mail.adlin.lab`)
    via CA FreeIPA, renouvellement automatique
- **Rôle `nextcloud`** — Nextcloud 33 sur Apache + PHP 8.3 (Remi) avec
  authentification LDAP FreeIPA entièrement automatisée via `occ` :
  - `user_ldap` activé et configuré (serveur, filtre, bind DN) via `occ ldap:set-config`
  - `ipaUniqueID` comme attribut UUID — évite les doublons de comptes lors des
    reconnexions LDAP (valeur stable contrairement à `entryUUID`)
  - Accès restreint au groupe FreeIPA `nextcloud_users`
  - MariaDB locale (utf8mb4_unicode_ci), données hors webroot dans `/var/nc_data`
  - Certificat TLS double-SAN (`cloud01.adlin.lab` + `cloud.adlin.lab`) via
    certmonger/Dogtag, renouvellement automatique
  - `AllowEncodedSlashes NoDecode` — requis pour CalDAV/CardDAV avec Apache
  - SELinux enforcing (`httpd_sys_rw_content_t` sur `/var/nc_data`), HTTPS
    uniquement (443/tcp)
- **Rôle `odoo`** — Odoo 19 CE via RPM nightly officiel avec authentification
  FreeIPA LDAP (module `auth_ldap` activé automatiquement via CLI) :
  - PostgreSQL local (peer authentication — pas de mot de passe TCP)
  - Workers multi-process (4 workers + longpolling port 8072)
  - `proxy_mode = True` — indispensable derrière nginx (X-Forwarded-Proto → HTTPS)
  - Guards idempotents : init base (table `ir_module_module`) + auth_ldap (state)
  - Pas de TLS sur erp01 — proxy01 termine le TLS, Odoo écoute en HTTP
  - Configuration LDAP post-déploiement documentée (Settings → Technical → LDAP)
- **Tooling** — Makefile (cibles `make deploy-*`), playbook `verify.yml`
  (smoke tests SELinux, chrony, Kerberos, nginx, certmonger), Ansible Vault avec
  pattern d'indirection `vars.yml` / `vault.yml`, ansible-lint et yamllint
- **Rôle `rocketchat`** — Rocket.Chat 8.x via Docker Compose, sync LDAP/groupes FreeIPA
- **Rôle `freepbx`** — FreePBX 17 + Asterisk 21 sur Debian 12, enrollment IPA SSH/sudo

### Périmètre cible

L'architecture, le plan de déploiement et le diagramme ci-dessous décrivent le
périmètre cible final du projet, c'est-à-dire l'objectif vers lequel le dépôt
converge, et non l'état du code à date.

---

## Architecture

```
                        ┌─────────────────────────────────────┐
                        │  ThinkCentre M920q — Proxmox VE      │
                        │  Intel i9-9900T · 24 Go RAM          │
                        └────────────────┬────────────────────┘
                                         │
           ┌─────────────────────────────┼─────────────────────────────┐
           │                             │                             │
    ┌──────▼──────┐               ┌──────▼──────┐              ┌──────▼──────┐
    │   ipa01     │               │  proxy01    │              │  cloud01    │
    │ Rocky 9     │               │  Rocky 9    │              │  Rocky 9    │
    │ FreeIPA     │◄──────────────│  Nginx      │◄─────────────│  Nextcloud  │
    │ DNS · PKI   │   LDAPS/636   │  TLS        │   reverse    │  Apache     │
    │ Kerberos    │               │  certmonger │   proxy      │  PHP 8.3    │
    └─────────────┘               └──────┬──────┘              └─────────────┘
           ▲                             │
           │  LDAP/Kerberos              │ reverse proxy
           │  auth (tous services)       │
    ┌──────┴──────────────────────────────────────────────────────────┐
    │                             │              │          │          │
┌───▼─────┐               ┌──────▼──────┐ ┌────▼────┐ ┌───▼────┐ ┌──▼─────┐
│ mail01  │               │   erp01     │ │ chat01  │ │ pbx01  │ │        │
│ Rocky 9 │               │   Rocky 9   │ │ Rocky 9 │ │Debian12│ │        │
│Postfix  │               │   Odoo 19   │ │Rocket.  │ │FreePBX │ │        │
│Dovecot  │               │   CE        │ │Chat 8.x │ │   17   │ │        │
│SOGo     │               │   PostgreSQL│ │MongoDB  │ │Asterisk│ │        │
│Rspamd   │               │             │ │(Docker) │ │   21   │ │        │
└─────────┘               └─────────────┘ └─────────┘ └────────┘ └────────┘
```

### Ce que chaque service remplace

| Service déployé | Remplace |
|---|---|
| Postfix + Dovecot + SOGo + Rspamd | Microsoft 365 Outlook / Exchange, Google Workspace Gmail |
| Nextcloud 33 | Google Drive, OneDrive/SharePoint, Dropbox Business |
| Odoo 19 Community Edition | HubSpot CRM, Salesforce, Zoho CRM, Sage |
| Rocket.Chat 8.x | Slack, Microsoft Teams Chat, Google Chat |
| FreePBX 17 / Asterisk 21 | Zoom Phone, Teams Phone, RingCentral |
| FreeIPA | Active Directory, Azure AD, Okta |

---

## Stack technique

| Couche | Technologie | Notes |
|---|---|---|
| Hyperviseur | Proxmox VE | Hôte — non géré par Ansible |
| OS serveurs | Rocky Linux 9 | RHEL-compatible, SELinux enforcing |
| OS PBX | Debian 12 | Exception imposée par FreePBX 17 (abandon support RHEL 2024) |
| Identité (IdM) | FreeIPA (389-DS + Kerberos + Dogtag + BIND9) | Socle de tout le reste |
| Automatisation | Ansible + collections Galaxy + Vault | Rôles structurés, idempotents |
| PKI interne | Dogtag CA (intégré FreeIPA) | Certificats services internes |
| DNS | BIND9 intégré FreeIPA | Résolution interne + zones inverses |
| Reverse proxy | Nginx + certmonger (CA FreeIPA) | TLS terminaison centrale |
| Secrets | Ansible Vault (AES-256) | Pattern `vars.yml` / `vault.yml` |

---

## Dimensionnement

| VM | OS | vCPUs | RAM | Disque |
|---|---|---|---|---|
| ipa01 | Rocky Linux 9 | 2 | 4 Go | 20 Go |
| proxy01 | Rocky Linux 9 | 1 | 512 Mo | 10 Go |
| cloud01 | Rocky Linux 9 | 2 | 4 Go | 100+ Go |
| mail01 | Rocky Linux 9 | 2 | 3 Go | 50 Go |
| erp01 | Rocky Linux 9 | 2 | 4 Go | 50 Go |
| chat01 | Rocky Linux 9 | 1 | 2 Go | 30 Go |
| pbx01 | Debian 12 | 1 | 1,5 Go | 20 Go |
| **Total** | | **11 vCPUs** | **19 Go** | **280 Go** |

Marge disponible sur le ThinkCentre M920q : 5 Go RAM, 5 threads CPU.

---

## Structure du dépôt

```
adlin/
├── README.md
├── LICENSE                            # MIT
├── ansible.cfg
├── Makefile                           # make deploy-freeipa, make deploy-all
├── requirements.yml                   # Collections Galaxy (ansible.posix, community.general, community.postgresql, freeipa…)
│
├── inventory/
│   ├── production/
│   │   ├── hosts.yml
│   │   ├── group_vars/
│   │   │   ├── all/
│   │   │   │   ├── vars.yml           # Variables publiques (réfs vault)
│   │   │   │   └── vault.yml          # Secrets chiffrés AES-256
│   │   │   ├── ipaservers.yml
│   │   │   ├── mailservers.yml
│   │   │   ├── nextcloud.yml
│   │   │   ├── pbx.yml
│   │   │   ├── odoo.yml
│   │   │   └── chat.yml
│   │   └── host_vars/
│   │       └── ipa01.example.com.yml
│   └── staging/                       # Miroir pour tests
│
├── playbooks/
│   ├── site.yml                       # Master — importe tous les playbooks
│   ├── 00-common.yml                  # Hardening OS, chrony, EPEL, IPA client
│   ├── 01-freeipa-server.yml
│   ├── 02-reverse-proxy.yml
│   ├── 03-nextcloud.yml
│   ├── 04-mailserver.yml
│   ├── 05-odoo.yml
│   ├── 06-rocketchat.yml
│   └── 07-freepbx.yml
│
├── roles/
│   ├── common/                        # Hardening OS, SELinux, firewalld, IPA client  ✅
│   ├── freeipa_server/                # FreeIPA Server, DNS, PKI, comptes de service  ✅
│   ├── reverse_proxy/                 # Nginx + certmonger/FreeIPA PKI               ✅
│   ├── mailserver/                    # Postfix + Dovecot + SOGo + Rspamd            ✅
│   ├── nextcloud/                     # Nextcloud 33, Apache/PHP 8.3, MariaDB, LDAP   ✅
│   ├── odoo/                          # Odoo 19 CE, PostgreSQL peer auth, auth_ldap   ✅
│   ├── rocketchat/                    # Rocket.Chat 8.x Docker Compose, LDAP FreeIPA   ✅
│   └── freepbx/                       # FreePBX 17 + Asterisk 21, enrollment IPA       ✅
│
└── .gitignore
```

---

## Prérequis

**Poste de contrôle Ansible**

```bash
# Fedora / Rocky Linux
sudo dnf install ansible-core python3-netaddr

# Collections et rôles Galaxy
ansible-galaxy install -r requirements.yml
```

**Proxmox VE**

- Version 8.x minimum recommandée
- Réseau : bridge `vmbr0` configuré, accès SSH depuis le poste Ansible
- Stockage : LVM-thin ou ZFS (thin provisioning recommandé)

---

## Déploiement

### 1. Configuration initiale

```bash
# Cloner le dépôt
git clone https://github.com/<username>/adlin.git
cd adlin

# Créer le fichier de mot de passe vault (ne jamais commiter)
echo "votre_mot_de_passe_vault" > .vault_pass
chmod 600 .vault_pass

# Adapter l'inventaire
cp inventory/production/group_vars/all/vars.yml.example \
   inventory/production/group_vars/all/vars.yml
# Éditer vars.yml : domaine, IPs, paramètres LDAP

# Chiffrer les secrets
ansible-vault encrypt inventory/production/group_vars/all/vault.yml
```

### 2. Déploiement complet (ordre respectant les dépendances)

```bash
# Infrastructure complète
ansible-playbook -i inventory/production playbooks/site.yml \
  --vault-password-file .vault_pass

# Ou service par service
make deploy-freeipa     # Phase 1 — socle obligatoire
make deploy-proxy       # Phase 2 — TLS avant tout autre service
make deploy-nextcloud   # Phase 3
make deploy-mail        # Phase 3
make deploy-rocketchat  # Phase 3
make deploy-odoo        # Phase 4
make deploy-freepbx     # Phase 4
```

### 3. Vérification post-déploiement

```bash
# Tester l'authentification FreeIPA sur tous les services
ansible-playbook -i inventory/production playbooks/verify.yml \
  --vault-password-file .vault_pass

# Vérifier SELinux (doit retourner "enforcing" sur toutes les VM Rocky Linux)
ansible all -i inventory/production -m command -a "getenforce" \
  --vault-password-file .vault_pass
```

---

## Intégration FreeIPA

FreeIPA est le **seul point de vérité** pour l'identité. Chaque service
dispose d'un compte de service dédié dans `cn=sysaccounts,cn=etc` avec des
droits en lecture seule sur l'annuaire.

```
Utilisateur créé dans FreeIPA
        │
        ▼
┌───────────────────────────────────────────────────────┐
│  Propagation automatique vers :                        │
│  · Nextcloud    (user_ldap + ipaUniqueID override)    │
│  · SOGo         (authentification + CalDAV/CardDAV)   │
│  · Odoo         (module auth_ldap)                    │
│  · Rocket.Chat  (sync groupes inclus, édition free)   │
│  · FreePBX      (client IPA SSH uniquement)           │
└───────────────────────────────────────────────────────┘
```

**Comptes de service provisionnés automatiquement par Ansible :**

| Service | DN |
|---|---|
| Nextcloud | `uid=svc_nextcloud,cn=sysaccounts,cn=etc,dc=example,dc=com` |
| Mail | `uid=svc_mail,cn=sysaccounts,cn=etc,dc=example,dc=com` |
| Odoo | `uid=svc_odoo,cn=sysaccounts,cn=etc,dc=example,dc=com` |
| Rocket.Chat | `uid=svc_rocketchat,cn=sysaccounts,cn=etc,dc=example,dc=com` |

---

## Sécurité

**SELinux**

Toutes les VM Rocky Linux 9 opèrent en mode `enforcing`. Chaque rôle Ansible
documente et configure explicitement les booleans et contextes fichiers requis
— aucun `setenforce 0` n'est utilisé.

```yaml
# Exemple extrait de roles/reverse_proxy/tasks/selinux.yml
- name: "selinux | Activer les booleans requis par nginx reverse proxy"
  ansible.posix.seboolean:
    name: "{{ item }}"
    state: true
    persistent: true
  loop:
    - httpd_can_network_connect      # connexions sortantes vers les upstreams
    - httpd_can_network_connect_db   # accès DB si nginx interroge directement
```

**Firewalld**

Chaque VM expose uniquement les ports strictement nécessaires à son rôle.
La gestion est centralisée dans `roles/<service>/tasks/firewalld.yml`.

**Ansible Vault**

Pattern d'indirection `vars.yml` / `vault.yml` : les variables publiques
référencent des variables vault (`ldap_password: "{{ vault_ldap_password }}"`).
Seul `vault.yml` est chiffré. Les deux fichiers sont commités — seul le
fichier `.vault_pass` est exclu via `.gitignore`.

---

## Choix architecturaux notables

**Pourquoi Postfix + Dovecot + SOGo plutôt que Mailcow ?**
Mailcow est une excellente solution, mais elle repose sur Docker, ce qui impose
SELinux en mode permissif et introduit des conflits avec firewalld. La stack
native RPM est la seule option offrant simultanément FreeIPA LDAP/Kerberos natif,
SELinux enforcing et des packages maintenus par RHEL/EPEL.

**Pourquoi Rocket.Chat plutôt que Mattermost ?**
La synchronisation LDAP (y compris les groupes) est gratuite dans l'édition
Community de Rocket.Chat. Chez Mattermost, cette fonctionnalité est réservée
à l'édition Enterprise payante.

**Pourquoi Debian 12 pour FreePBX ?**
Sangoma a officiellement abandonné le support Rocky Linux / RHEL en 2024.
C'est la seule exception à la règle Rocky Linux 9 dans ce projet, documentée
et justifiée explicitement.

**Pourquoi Odoo 19 CE plutôt que SuiteCRM ou EspoCRM ?**
Odoo couvre à la fois le CRM et l'ERP (facturation, inventaire, RH) avec
70+ modules, une communauté de 12M+ utilisateurs et une édition Community
sous licence LGPL. Les alternatives sont soit trop limitées fonctionnellement,
soit moins bien maintenues.

---

## Licence

MIT, voir [LICENSE](LICENSE).
