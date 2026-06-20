# ADLin — Open-Source SME Infrastructure on Proxmox VE

> Full replacement for a Microsoft 365 / Google Workspace / Salesforce stack
> using open-source self-hosted equivalents, deployed entirely via Ansible
> on Rocky Linux 9 with FreeIPA as the centralized identity backbone.

![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat-square&logo=ansible&logoColor=white)
![Rocky Linux](https://img.shields.io/badge/Rocky_Linux_9-10B981?style=flat-square&logo=rockylinux&logoColor=white)
![FreeIPA](https://img.shields.io/badge/FreeIPA-IdM-blue?style=flat-square)
![SELinux](https://img.shields.io/badge/SELinux-enforcing-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## Mission Statement

This project demonstrates the automated deployment of a complete IT infrastructure
for a small-to-medium business (10–200 employees), featuring:

- **Zero software licensing costs** — versus $12–50/user/month for a comparable
  Microsoft 365 + Salesforce + Zoom stack (your wallet will thank you)
- **SELinux in enforcing mode** on every Rocky Linux 9 VM — while most guides
  tell you to disable it, this project tells SELinux "you're welcome"
- **FreeIPA as the single source of truth** (LDAP + Kerberos + PKI + DNS) for
  every service, no exceptions, no excuses
- **Ansible, and only Ansible** — structured roles, idempotent tasks, commented
  code, secrets encrypted with Vault

---

## Status

> This repository is under active construction. The table below shows what's
> implemented and working today, versus the final target scope described in the
> architecture section.

### ✅ Implemented and functional

- **`common` role** — Rocky Linux 9 hardening: SELinux enforcing, EPEL/CRB,
  base packages, chrony (client or NTP server), FreeIPA client enrollment,
  firewalld
- **`freeipa_server` role** — Full FreeIPA Server deployment: integrated DNS,
  Dogtag PKI, KRA (Key Recovery Authority), LDAP service accounts in
  `cn=sysaccounts`, POSIX application groups, firewalld rules
- **`reverse_proxy` role** — Nginx with automated TLS via certmonger and the
  FreeIPA CA: Kerberos service principal, multi-SAN certificate, SELinux booleans,
  templated vhosts (Odoo longpolling support), HSTS and security headers
- **`mailserver` role** — Complete mail stack with FreeIPA LDAP authentication:
  - Postfix: MTA, LDAP virtual mailboxes, LMTP delivery → Dovecot, submission
    SASL/STARTTLS (587), antispam filter via Rspamd milter
  - Dovecot: IMAPS (993), FreeIPA `auth_bind` (your password never touches the
    directory—magic), virtual Maildir storage, ManageSieve (4190)
  - Rspamd: milter-based antispam, Redis cache (bayes, rate limiting)
  - SOGo: webmail + CalDAV + CardDAV + ActiveSync, PostgreSQL backend, local
    nginx frontend (proxy01 → mail01:80 → sogod:20000)
  - certmonger: multi-SAN certificate (`mail01.adlin.lab` + `mail.adlin.lab`)
    via FreeIPA CA, automatic renewal
- **`nextcloud` role** — Nextcloud on Apache + PHP with fully automated FreeIPA LDAP
    authentication via `occ`:
  - `user_ldap` enabled and configured (server, filter, bind DN) via `occ ldap:set-config`
  - `ipaUniqueID` as UUID attribute — prevents duplicate accounts on LDAP
    reconnections (stable value, unlike `entryUUID` which has commitment issues)
  - Access restricted to FreeIPA `nextcloud_users` group
  - Local MariaDB (utf8mb4_unicode_ci), data outside webroot in `/var/nc_data`
  - Dual-SAN TLS certificate (`cloud01.adlin.lab` + `cloud.adlin.lab`) via
    certmonger/Dogtag, automatic renewal
  - `AllowEncodedSlashes NoDecode` — required for CalDAV/CardDAV with Apache
  - SELinux enforcing (`httpd_sys_rw_content_t` on `/var/nc_data`), HTTPS
    only (443/tcp)
- **`odoo` role** — Odoo Community Edition via official nightly RPM with FreeIPA LDAP
  authentication (module `auth_ldap` enabled automatically via CLI):
  - Local PostgreSQL (peer authentication — no TCP password to leak)
  - Multi-process workers (4 workers + longpolling port 8072)
  - `proxy_mode = True` — essential behind nginx (X-Forwarded-Proto → HTTPS)
  - Idempotent guards: database init (table `ir_module_module`) + auth_ldap (state)
  - No TLS on erp01 — proxy01 terminates TLS, Odoo listens in HTTP bliss
  - Post-deploy LDAP configuration documented (Settings → Technical → LDAP)
- **`rocketchat` role** — Rocket.Chat via Docker Compose, FreeIPA LDAP/group sync
- **`freepbx` role** — FreePBX + Asterisk on Debian, IPA SSH/sudo enrollment
- **Tooling** — Makefile (`make deploy-*` targets), `verify.yml` playbook
  (smoke tests: SELinux, chrony, Kerberos, nginx, certmonger), Ansible Vault with
  `vars.yml` / `vault.yml` indirection pattern, ansible-lint and yamllint

---

## Architecture

```
                        ┌─────────────────────────────────────┐
                        │  ThinkCentre M920q — Proxmox VE     │
                        │  Intel i9-9900T · 24 GB RAM         │
                        └────────────────┬────────────────────┘
                                         │
           ┌─────────────────────────────┼─────────────────────────────┐
           │                             │                             │
    ┌──────▼──────┐               ┌──────▼──────┐              ┌──────▼──────┐
    │   ipa01     │               │  proxy01    │              │  cloud01    │
    │ Rocky 9     │               │  Rocky 9    │              │  Rocky 9    │
    │ FreeIPA     │◄──────────────│  Nginx      │◄─────────────│  Nextcloud  │
    │ DNS · PKI   │   LDAPS/636   │  TLS        │   reverse    │  Apache     │
    │ Kerberos    │               │  certmonger │   proxy      │  PHP        │
    └─────────────┘               └──────┬──────┘              └─────────────┘
           ▲                             │
           │  LDAP/Kerberos              │ reverse proxy
           │  auth (all services)        │
    ┌──────┴──────────────────────────────────────────────────────────┐
    │                            |             |          |           |
┌───▼─────┐               ┌──────▼──────┐ ┌────▼────┐ ┌───▼────┐ ┌──▼─────┐
│ mail01  │               │   erp01     │ │ chat01  │ │ pbx01  │ │        │
│ Rocky 9 │               │   Rocky 9   │ │ Rocky 9 │ │Debian12│ │        │
│Postfix  │               │   Odoo      │ │Rocket.  │ │FreePBX │ │        │
│Dovecot  │               │   CE        │ │Chat     │ │        │ │        │
│SOGo     │               │   PostgreSQL│ │MongoDB  │ │Asterisk│ │        │
│Rspamd   │               │             │ │(Docker) │ │        │ │        │
└─────────┘               └─────────────┘ └─────────┘ └────────┘ └────────┘
```

### What each service replaces

| Deployed service | Replaces |
|---|---|
| Postfix + Dovecot + SOGo + Rspamd | Microsoft 365 Outlook / Exchange, Google Workspace Gmail |
| Nextcloud | Google Drive, OneDrive/SharePoint, Dropbox Business |
| Odoo Community Edition | HubSpot CRM, Salesforce, Zoho CRM, Sage |
| Rocket.Chat | Slack, Microsoft Teams Chat, Google Chat |
| FreePBX / Asterisk | Zoom Phone, Teams Phone, RingCentral |
| FreeIPA | Active Directory, Azure AD, Okta |

---

## Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Hypervisor | Proxmox VE | Host — not managed by Ansible |
| Server OS | Rocky Linux 9 | RHEL-compatible, SELinux enforcing |
| PBX OS | Debian 12 | Exception forced by FreePBX 17 (RHEL support dropped in 2024) |
| Identity (IdM) | FreeIPA (389-DS + Kerberos + Dogtag + BIND9) | Foundation of everything else |
| Automation | Ansible + Galaxy collections + Vault | Structured roles, idempotent |
| Internal PKI | Dogtag CA (FreeIPA-integrated) | Internal service certificates |
| DNS | BIND9 (FreeIPA-integrated) | Internal resolution + reverse zones |
| Reverse proxy | Nginx + certmonger (FreeIPA CA) | Central TLS termination |
| Secrets | Ansible Vault (AES-256) | `vars.yml` / `vault.yml` pattern |

---

## Sizing

| VM | OS | vCPUs | RAM | Disk |
|---|---|---|---|---|
| ipa01 | Rocky Linux 9 | 2 | 4 GB | 20 GB |
| proxy01 | Rocky Linux 9 | 1 | 512 MB | 10 GB |
| cloud01 | Rocky Linux 9 | 2 | 4 GB | 100+ GB |
| mail01 | Rocky Linux 9 | 2 | 3 GB | 50 GB |
| erp01 | Rocky Linux 9 | 2 | 4 GB | 50 GB |
| chat01 | Rocky Linux 9 | 1 | 2 GB | 30 GB |
| pbx01 | Debian 12 | 1 | 1.5 GB | 20 GB |
| **Total** | | **11 vCPUs** | **19 GB** | **280 GB** |

Headroom left on the ThinkCentre M920q: 5 GB RAM, 5 CPU threads.

---

## Repository Structure

```
adlin/
├── README.md
├── LICENSE                            # MIT
├── ansible.cfg
├── Makefile                           # make deploy-freeipa, make deploy-all
├── requirements.yml                   # Galaxy collections (ansible.posix, community.general, community.postgresql, freeipa…)
│
├── inventory/
│   ├── production/
│   │   ├── hosts.yml
│   │   ├── group_vars/
│   │   │   ├── all/
│   │   │   │   ├── vars.yml           # Public variables (vault refs)
│   │   │   │   └── vault.yml          # Encrypted secrets AES-256
│   │   │   └── ipaservers.yml         # FreeIPA overrides (NTP, enrollment)
│
├── playbooks/
│   ├── site.yml                       # Master — imports all playbooks
│   ├── 00-common.yml                  # OS hardening, chrony, EPEL, IPA client
│   ├── 01-freeipa-server.yml
│   ├── 02-reverse-proxy.yml
│   ├── 03-nextcloud.yml
│   ├── 04-mailserver.yml
│   ├── 05-rocketchat.yml
│   ├── 06-odoo.yml
│   └── 07-freepbx.yml
│
├── roles/
│   ├── common/                        # OS hardening, SELinux, firewalld, IPA client ✅
│   ├── freeipa_server/                # FreeIPA Server, DNS, PKI, service accounts   ✅
│   ├── reverse_proxy/                 # Nginx + certmonger/FreeIPA PKI               ✅
│   ├── mailserver/                    # Postfix + Dovecot + SOGo + Rspamd            ✅
│   ├── nextcloud/                     # Nextcloud, Apache/PHP, MariaDB, LDAP         ✅
│   ├── odoo/                          # Odoo CE, PostgreSQL peer auth, auth_ldap     ✅
│   ├── rocketchat/                    # Rocket.Chat Docker Compose, FreeIPA LDAP     ✅
│   └── freepbx/                       # FreePBX + Asterisk, IPA enrollment           ✅
│
└── .gitignore
```

---

## Prerequisites

**Ansible control node**

```bash
# Fedora / Rocky Linux
sudo dnf install ansible-core python3-netaddr

# Galaxy collections and roles
ansible-galaxy install -r requirements.yml
```

**Proxmox VE**

- Version 8.x minimum recommended
- Network: bridge `vmbr0` configured, SSH access from the Ansible control node
- Storage: LVM-thin or ZFS (thin provisioning recommended)

---

## Deployment

### 1. Initial setup

```bash
# Clone the repository
git clone https://github.com/<username>/adlin.git
cd adlin

# Create the vault password file (NEVER commit this)
echo "your_vault_password" > .vault_pass
chmod 600 .vault_pass

# Adapt the inventory
# Edit vars.yml: domain, IPs, LDAP parameters
# The file already exists — adjust values to your environment

# Encrypt secrets
ansible-vault encrypt inventory/production/group_vars/all/vault.yml
```

### 2. Full deployment (respecting dependency order)

```bash
# Full infrastructure
ansible-playbook -i inventory/production playbooks/site.yml \
  --vault-password-file .vault_pass

# Or service by service
make deploy-freeipa     # Phase 1 — mandatory foundation
make deploy-proxy       # Phase 2 — TLS before any other service
make deploy-nextcloud   # Phase 3
make deploy-mail        # Phase 3
make deploy-rocketchat  # Phase 3
make deploy-odoo        # Phase 4
make deploy-freepbx     # Phase 4
```

### 3. Post-deployment verification

```bash
# Test FreeIPA authentication across all services
ansible-playbook -i inventory/production playbooks/verify.yml \
  --vault-password-file .vault_pass

# Verify SELinux (must return "Enforcing" on all Rocky Linux VMs)
ansible all -i inventory/production -m command -a "getenforce" \
  --vault-password-file .vault_pass
```

---

## FreeIPA Integration

FreeIPA is the **single source of truth** for identity. Each service has its
own dedicated service account in `cn=sysaccounts,cn=etc` with read-only access
to the directory. Think of it as Active Directory without the "please reboot
three times" ceremony.

```
User created in FreeIPA
        │
        ▼
┌───────────────────────────────────────────────────────┐
│  Automatic propagation to:                            │
│  · Nextcloud    (user_ldap + ipaUniqueID override)    │
│  · SOGo         (authentication + CalDAV/CardDAV)     │
│  · Odoo         (auth_ldap module)                    │
│  · Rocket.Chat  (group sync included, free edition)   │
│  · FreePBX      (IPA client SSH only)                 │
└───────────────────────────────────────────────────────┘
```

**Service accounts provisioned automatically by Ansible:**

| Service | DN |
|---|---|
| Nextcloud | `uid=svc_nextcloud,cn=sysaccounts,cn=etc,dc=adlin,dc=lab` |
| Mail | `uid=svc_mail,cn=sysaccounts,cn=etc,dc=adlin,dc=lab` |
| Odoo | `uid=svc_odoo,cn=sysaccounts,cn=etc,dc=adlin,dc=lab` |
| Rocket.Chat | `uid=svc_rocketchat,cn=sysaccounts,cn=etc,dc=adlin,dc=lab` |

---

## Security

**SELinux**

All Rocky Linux 9 VMs run in `enforcing` mode. Every Ansible role explicitly
documents and configures the required booleans and file contexts — no
`setenforce 0` was harmed in the making of this project.

```yaml
# Excerpt from roles/reverse_proxy/tasks/selinux.yml
- name: "selinux | Enable booleans required by nginx reverse proxy"
  ansible.posix.seboolean:
    name: "{{ item }}"
    state: true
    persistent: true
  loop:
    - httpd_can_network_connect      # outbound connections to upstreams
    - httpd_can_network_connect_db   # DB access if nginx queries directly
```

**Firewalld**

Each VM exposes only the ports strictly required by its role.
Configuration is centralized in `roles/<service>/tasks/firewalld.yml`.

**Ansible Vault**

`vars.yml` / `vault.yml` indirection pattern: public variables reference vault
variables (`ldap_password: "{{ vault_ldap_password }}"`). Only `vault.yml` is
encrypted. Both files are committed — only `.vault_pass` is excluded via
`.gitignore`.

---

## Notable Architectural Choices

**Why Postfix + Dovecot + SOGo instead of Mailcow?**
Mailcow is a great solution, but it relies on Docker, which forces SELinux into
permissive mode and introduces conflicts with firewalld. The native RPM stack
is the only option that simultaneously offers native FreeIPA LDAP/Kerberos,
SELinux enforcing, and packages maintained by RHEL/EPEL. Also, it makes you
feel closer to the metal — and your inner greybeard approves.

**Why Rocket.Chat instead of Mattermost?**
LDAP synchronization (including groups) is free in Rocket.Chat's Community
edition. In Mattermost, this feature is locked behind the Enterprise paywall.
Our wallet made the choice for us.

**Why Debian 12 for FreePBX?**
Sangoma officially dropped Rocky Linux / RHEL support in 2024. This is the
single exception to the Rocky Linux 9 rule in this project, explicitly
documented and justified. We didn't choose Debian because we like `apt` better,
we chose it because FreePBX made us. Yes, we're still a bit bitter about it.

**Why Odoo Community Edition instead of SuiteCRM or EspoCRM?**
Odoo covers both CRM and ERP (invoicing, inventory, HR) with 70+ modules,
a community of 12M+ users, and a Community edition under LGPL license.
Alternatives are either too limited functionally or less well maintained.
Plus, "Odoo" is more fun to say.

---

## License

MIT, see [LICENSE](LICENSE).
