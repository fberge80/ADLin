# ADLin — Agent Instructions

## Repo Type
Ansible infrastructure-as-code project deploying a complete open-source SME IT stack on Proxmox VE with Rocky Linux 9 and FreeIPA.

## Critical Commands
```bash
# Install prerequisites (Fedora/Rocky)
sudo dnf install ansible-core python3-netaddr
ansible-galaxy install -r requirements.yml

# Deployment (order matters - see phases below)
make deploy-freeipa    # Phase 1b: FreeIPA must be deployed FIRST
make deploy-proxy      # Phase 2: TLS proxy before any services
make deploy-all       # Full deployment via site.yml

# Verification
make verify           # Run all smoke tests
make lint             # yamllint + ansible-lint

# Target specific hosts
echo "LIMIT=ipa01.adlin.lab make deploy-common"
```

## Deployment Phases (MUST follow this order)
1. **Phase 1a**: `make deploy-common` — OS hardening (SELinux enforcing, firewalld, chrony, IPA client enrollment)
2. **Phase 1b**: `make deploy-freeipa` — FreeIPA Server (DNS, PKI, KRA, service accounts)
3. **Phase 2**: `make deploy-proxy` — Reverse proxy with TLS (nginx + certmonger)
4. **Phase 3**: `make deploy-nextcloud`, `make deploy-mail`, `make deploy-rocketchat` — Productivity services
5. **Phase 4**: `make deploy-odoo`, `make deploy-freepbx` — Business services

**Never skip phases** — services depend on FreeIPA and TLS being operational first.

## Architecture Facts
- **FreeIPA is the single source of truth** for all identity — every service authenticates via LDAP/Kerberos
- **SELinux enforcing on all Rocky Linux 9 VMs** — no exceptions, roles configure required booleans
- **pbx01 runs Debian 12** — only exception (FreePBX dropped RHEL support in 2024)
- **proxy01 terminates TLS** — Odoo, Nextcloud, and other services run HTTP behind nginx
- **certmonger + FreeIPA CA** — automatic TLS certificate management for all services

## Inventory Structure
- `inventory/production/hosts.yml` — defines all VMs and groups
- `inventory/production/group_vars/` — per-group variables
  - `all/vars.yml` — public variables (references vault variables)
  - `all/vault.yml` — encrypted secrets (AES-256)
  - `*.yml` — group-specific overrides (e.g., `ipaservers.yml`, `mailservers.yml`)
- `rocky_hosts` group — all Rocky Linux 9 VMs (excludes pbx01)

## Vault Pattern
- **Indirection**: `vars.yml` contains `variable: "{{ vault_variable }}"` references
- **Only `vault.yml` is encrypted** — both `vars.yml` and `vault.yml` are committed
- **`.vault_pass` is gitignored** — never commit this file

## Role Structure
Each role in `roles/<service>/` follows:
- `tasks/main.yml` — primary tasks
- `tasks/firewalld.yml` — firewall rules for that service
- `tasks/selinux.yml` — SELinux booleans and file contexts
- `tasks/ipa_service.yml` — FreeIPA service principal and keytab setup
- `handlers/main.yml` — service restart handlers
- `defaults/main.yml` — default variables
- `meta/main.yml` — role metadata and dependencies

## Service Accounts
FreeIPA service accounts are auto-provisioned in `cn=sysaccounts,cn=etc,dc=adlin,dc=lab`:
- `svc_nextcloud`, `svc_mail`, `svc_odoo`, `svc_rocketchat`

## Verification
- `make verify` runs smoke tests for all services
- Tests check: SELinux enforcing, chrony sync, firewalld active, service health, port availability
- **All Rocky Linux VMs must return `Enforcing` for `getenforce`**

## Key Files
- `ansible.cfg` — Ansible configuration (inventory path, vault file, pipelining enabled)
- `Makefile` — wrapper for all deployment commands
- `requirements.yml` — Ansible Galaxy collections
- `.yamllint` — YAML linting rules (line-length: 160)

## Quirks
- **No Docker for mail stack** — Postfix/Dovecot/SOGo/Rspamd are native RPM to maintain SELinux enforcing
- **Rocket.Chat uses Docker** — only Docker-based service (MongoDB dependency)
- **Odoo runs HTTP** — proxy01 terminates TLS, Odoo listens on 8069/8072
- **Nextcloud data** — stored in `/var/nc_data` (outside webroot) with proper SELinux context
- **FreePBX SSH enrollment** — uses IPA SSH keys for sudo access (no LDAP auth)

## Testing
- No unit tests — verification is done via `playbooks/verify.yml` (integration smoke tests)
- Each service playbook in verify.yml checks: service running, ports listening, TLS certs valid
- Run specific verification: `ansible-playbook -i inventory/production playbooks/verify.yml --vault-password-file .vault_pass --limit <group>`

## Environment
- Control node: Fedora/Rocky Linux with ansible-core
- Target nodes: Rocky Linux 9 (except pbx01: Debian 12)
- Python: `/usr/bin/python3` on all nodes
- SSH: `~/.ssh/adlin_ansible` private key, `ansible` user with sudo
