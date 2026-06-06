# Fichiers contenant des placeholders à remplacer avant déploiement
#
# Généré par l'audit du 2026-06-06.
# Remplacer toutes les occurrences de [IP_ADDRESS] et [EMAIL]
# par les valeurs réelles de votre environnement.

## [IP_ADDRESS] — 19 occurrences dans 6 fichiers

### 1. inventory/production/hosts.yml (7 occurrences)
# Adresses IP de chaque VM dans Proxmox VE :
ipa01.adlin.lab    → [IP_ADDRESS]  # FreeIPA Server
proxy01.adlin.lab  → [IP_ADDRESS]  # Reverse proxy Nginx
mail01.adlin.lab   → [IP_ADDRESS]  # Stack mail
cloud01.adlin.lab  → [IP_ADDRESS]  # Nextcloud
erp01.adlin.lab    → [IP_ADDRESS]  # Odoo
chat01.adlin.lab   → [IP_ADDRESS]  # Rocket.Chat
pbx01.adlin.lab    → [IP_ADDRESS]  # FreePBX (Debian 12)

### 2. roles/reverse_proxy/defaults/main.yml (5 occurrences)
# URLs upstream des vhosts — pointer vers l'IP réelle de chaque backend :
reverse_proxy_vhosts:
  - name: cloud   → upstream_url: "http://[IP_ADDRESS]"        # cloud01
  - name: mail    → upstream_url: "http://[IP_ADDRESS]"        # mail01
  - name: erp     → upstream_url: "http://[IP_ADDRESS]:8069"   # erp01
                    longpolling_url: "http://[IP_ADDRESS]:8072" # erp01
  - name: chat    → upstream_url: "http://[IP_ADDRESS]:3000"   # chat01
  - name: pbx     → upstream_url: "http://[IP_ADDRESS]"        # pbx01

### 3. playbooks/verify.yml (6 occurrences)
# Tests wait_for — pointer vers l'IP de la VM ciblée :
Section Nextcloud      → host: "[IP_ADDRESS]"  # cloud01, port 443
Section mailserver     → host: "[IP_ADDRESS]"  # mail01, port 25
Section mailserver     → host: "[IP_ADDRESS]"  # mail01, port 993
Section Odoo           → url: "http://[IP_ADDRESS]:8069/web/login"  # erp01
Section Odoo           → host: "[IP_ADDRESS]"  # erp01, port 8072
Section Rocket.Chat    → host: "[IP_ADDRESS]"  # chat01, port 3000
Section FreePBX        → host: "[IP_ADDRESS]"  # pbx01, port 80

### 4. roles/mailserver/defaults/main.yml (1 occurrence)
# Bind Rspamd milter :
mailserver_rspamd_milter_bind: "[IP_ADDRESS]:11332"

### 5. roles/rocketchat/tasks/compose.yml (1 occurrence)
# Attente que Rocket.Chat réponde :
host: "[IP_ADDRESS]"  # chat01

### 6. roles/common/defaults/main.yml (1 occurrence)
# Réseau autorisé pour le serveur NTP (ipa01 uniquement) :
common_ntp_serve_network: "[IP_ADDRESS]/24"

## [EMAIL] — 1 occurrence

### 7. roles/rocketchat/defaults/main.yml (1 occurrence)
rocketchat_admin_email: "[EMAIL]"
