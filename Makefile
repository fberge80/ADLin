# Makefile, wrapper pour les commandes ansible-playbook ADLin.
# Usage : make help

ANSIBLE_PLAYBOOK := ansible-playbook
INVENTORY        := inventory/production
VAULT_FILE       := .vault_pass
PLAYBOOK_DIR     := playbooks

# Variable optionnelle pour cibler un host ou un groupe.
# Exemples :
#   make ping LIMIT=ipa01.adlin.lab
#   make deploy-common LIMIT=proxy01.adlin.lab
#   make deploy-common LIMIT=ipaservers,proxies
LIMIT ?=
LIMIT_OPT := $(if $(LIMIT),--limit $(LIMIT))

# Vérification que .vault_pass existe avant toute commande qui en a besoin
VAULT_OPTS := --vault-password-file $(VAULT_FILE)

.PHONY: help check-vault lint ping deploy-common deploy-freeipa deploy-proxy \
        deploy-nextcloud deploy-mail deploy-rocketchat deploy-odoo \
        deploy-freepbx deploy-all verify

help:
	@echo "Cibles disponibles :"
	@echo "  make ping                Tester la connectivité Ansible"
	@echo "  make lint                Lint YAML et ansible-lint"
	@echo ""
	@echo "  make deploy-common       Phase 1a, hardening OS toutes VM"
	@echo "  make deploy-freeipa      Phase 1b, FreeIPA Server sur ipa01"
	@echo "  make deploy-proxy        Phase 2,  reverse proxy sur proxy01"
	@echo "  make deploy-nextcloud    Phase 3a, Nextcloud sur cloud01"
	@echo "  make deploy-mail         Phase 3b, mail stack sur mail01"
	@echo "  make deploy-rocketchat   Phase 3c, Rocket.Chat sur chat01"
	@echo "  make deploy-odoo         Phase 4a, Odoo 19 CE sur erp01"
	@echo "  make deploy-freepbx      Phase 4b, FreePBX 17 sur pbx01"
	@echo ""
	@echo "  make deploy-all          Tous les playbooks via site.yml"
	@echo "  make verify              Tests d intégration FreeIPA"
	@echo ""
	@echo "Variable LIMIT, cibler un host ou un groupe :"
	@echo "  make ping          LIMIT=ipa01.adlin.lab"
	@echo "  make deploy-common LIMIT=proxy01.adlin.lab"
	@echo "  make deploy-common LIMIT=ipaservers,proxies"

check-vault:
	@test -f $(VAULT_FILE) || (echo "ERREUR : $(VAULT_FILE) introuvable" && exit 1)

ping:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/00-ping.yml $(LIMIT_OPT)

lint:
	@command -v ansible-lint >/dev/null || (echo "Installer ansible-lint" && exit 1)
	yamllint .
	ansible-lint

deploy-common: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/00-common.yml $(VAULT_OPTS) $(LIMIT_OPT)

deploy-freeipa: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/01-freeipa-server.yml $(VAULT_OPTS) $(LIMIT_OPT)

deploy-proxy: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/02-reverse-proxy.yml $(VAULT_OPTS) $(LIMIT_OPT)

deploy-nextcloud: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/03-nextcloud.yml $(VAULT_OPTS) $(LIMIT_OPT)

deploy-mail: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/04-mailserver.yml $(VAULT_OPTS) $(LIMIT_OPT)

deploy-rocketchat: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/06-rocketchat.yml $(VAULT_OPTS) $(LIMIT_OPT)

deploy-odoo: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/05-odoo.yml $(VAULT_OPTS) $(LIMIT_OPT)

deploy-freepbx: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/07-freepbx.yml $(VAULT_OPTS) $(LIMIT_OPT)

deploy-all: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/site.yml $(VAULT_OPTS) $(LIMIT_OPT)

verify: check-vault
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK_DIR)/verify.yml $(VAULT_OPTS) $(LIMIT_OPT)
