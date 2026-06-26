============================================================
ADLin — Procédure de test depuis VM 106 (RockyKDE)
============================================================

Prérequis : VM 106 démarrée avec un 2e NIC sur vmbr1 (déjà fait).
La VM est accessible en console via Proxmox (192.168.0.249:8006 → VM 106 → Console).

═══════════════════════════════════════════════════════════
ÉTAPE 1 — Accès à la console de VM 106
═══════════════════════════════════════════════════════════

1. Ouvrir https://192.168.0.249:8006 dans le navigateur
2. Sélectionner "RockyKDE" (VMID 106) → Console
3. Se connecter en root

═══════════════════════════════════════════════════════════
ÉTAPE 2 — Configuration réseau vmbr1
═══════════════════════════════════════════════════════════

La VM a reçu une IP 10.10.10.160 via DHCP (dnsmasq sur Proxmox).
Vérifier et configurer si nécessaire :

```bash
# Vérifier les interfaces réseau
ip addr show

# Identifier l'interface vmbr1 (probablement ens19 ou eth1)
# Elle devrait déjà avoir 10.10.10.160/24 via DHCP.
# Si ce n'est pas le cas, l'activer manuellement :
sudo nmcli device connect <interface>

# Définir le DNS vers FreeIPA
sudo nmcli connection modify <nom_connexion_vmbr1> ipv4.dns 10.10.10.10
sudo nmcli connection up <nom_connexion_vmbr1>

# Vérifier la résolution DNS
dig ipa01.adlin.lab A @10.10.10.10 +short
# Doit retourner : 10.10.10.10
```

═══════════════════════════════════════════════════════════
ÉTAPE 3 — Créer un utilisateur test dans FreeIPA
═══════════════════════════════════════════════════════════

Depuis le bureau (poste de contrôle Ansible), exécuter :

```bash
cd ~/projects/ADLin
ansible ipa01.adlin.lab -i inventory/production --become -m shell -a "
echo '{{ ipa_admin_password }}' | kinit admin 2>/dev/null

# Créer l'utilisateur test (membre des groupes de service)
ipa user-add fdupond \
  --first=François \
  --last=Dupont \
  --password \
  --email=fdupond@adlin.lab 2>/dev/null || echo 'utilisateur existe déjà'

# Ajouter aux groupes d'accès des services
ipa group-add-member nextcloud_users --users=fdupond 2>/dev/null
ipa group-add-member chat_users --users=fdupond 2>/dev/null
ipa group-add-member odoo_users --users=fdupond 2>/dev/null

kdestroy -A 2>/dev/null
echo 'Utilisateur fdupond créé et ajouté aux groupes.'
" --vault-password-file .vault_pass
```

Le mot de passe demandé sera défini interactivement (noter le mdp choisi).
Si l'utilisateur existe déjà, passer à l'étape suivante.

═══════════════════════════════════════════════════════════
ÉTAPE 4 — Enroller VM 106 comme client FreeIPA
═══════════════════════════════════════════════════════════

Dans la console de VM 106 (root) :

```bash
# Installer le client FreeIPA
dnf install -y freeipa-client

# Enroller la VM dans le domaine ADLIN.LAB
ipa-client-install \
  --domain=adlin.lab \
  --realm=ADLIN.LAB \
  --server=ipa01.adlin.lab \
  --hostname=rockykde.adlin.lab \
  --mkhomedir \
  --no-nisdomain \
  --force-join \
  --principal=admin \
  --password=W5vsDztYX8bI8sdrpjRuxTmA \
  --unattended

# Vérifier l'enrollment
kinit admin
klist
ipa user-find admin
kdestroy

# Vérifier que le home directory est créé automatiquement
getent passwd fdupond@adlin.lab
# Devrait afficher les infos de l'utilisateur
```

Si `--unattended` échoue, enlever cette option et saisir le mot de passe admin interactivement.

═══════════════════════════════════════════════════════════
ÉTAPE 5 — Ajouter l'entrée DNS pour rockykde.adlin.lab
═══════════════════════════════════════════════════════════

Depuis le bureau :

```bash
cd ~/projects/ADLin
ansible ipa01.adlin.lab -i inventory/production --become -m shell -a "
echo '{{ ipa_admin_password }}' | kinit admin 2>/dev/null
ipa dnsrecord-add adlin.lab rockykde --a-rec=10.10.10.160 2>/dev/null || echo 'enregistrement existe déjà'
ipa dnsrecord-add adlin.lab rockykde --a-ip-address=10.10.10.160 2>/dev/null
kdestroy -A 2>/dev/null
echo 'DNS OK'
" --vault-password-file .vault_pass
```

═══════════════════════════════════════════════════════════
ÉTAPE 6 — Test de connexion utilisateur
═══════════════════════════════════════════════════════════

Dans la console de VM 106 :

```bash
# Se connecter en tant que fdupond
su - fdupond@adlin.lab
# Saisir le mot de passe défini à l'étape 3

# Vérifier l'identité
id
klist
```

═══════════════════════════════════════════════════════════
ÉTAPE 7 — Tests des services
═══════════════════════════════════════════════════════════

Tous les tests se font depuis VM 106, connecté en fdupond@adlin.lab.

--- 7A. Certificat TLS du proxy ---
```bash
# Vérifier que le certificat multi-SAN est valide
openssl s_client -connect proxy01.adlin.lab:443 -servername cloud01.adlin.lab </dev/null 2>/dev/null | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"
# Doit afficher les 6 SANs : proxy01, cloud01, mail01, erp01, chat01, pbx01
```

--- 7B. Nextcloud (cloud01) ---
```bash
# Test HTTP via proxy01
curl -skI https://cloud01.adlin.lab | head -5
# Doit retourner HTTP 200 ou redirect

# Ouvrir dans le navigateur : https://cloud01.adlin.lab
# Connexion avec fdupond@adlin.lab + mot de passe FreeIPA
```

--- 7C. Webmail SOGo (mail01) ---
```bash
# Test HTTP via proxy01
curl -skI https://mail01.adlin.lab/SOGo/ | head -5

# Ouvrir dans le navigateur : https://mail01.adlin.lab/SOGo/
# Connexion avec fdupond@adlin.lab + mot de passe FreeIPA
```

--- 7D. Rocket.Chat (chat01) ---
```bash
# Test HTTP via proxy01
curl -skI https://chat01.adlin.lab | head -5

# Ouvrir dans le navigateur : https://chat01.adlin.lab
# Connexion avec fdupond@adlin.lab + mot de passe FreeIPA
```

--- 7E. Odoo (erp01) ---
```bash
# Test HTTP via proxy01
curl -skI https://erp01.adlin.lab | head -5

# Ouvrir dans le navigateur : https://erp01.adlin.lab
# Connexion avec fdupond@adlin.lab + mot de passe FreeIPA
```

--- 7F. FreePBX (pbx01) ---
```bash
# Test HTTP (admin FreePBX)
curl -skI https://pbx01.adlin.lab/admin/ | head -5

# Ouvrir dans le navigateur : https://pbx01.adlin.lab/admin/
# Login admin FreePBX (créé par le script Sangoma)
```

--- 7G. FreeIPA (ipa01) ---
```bash
# Ouvrir dans le navigateur : https://ipa01.adlin.lab
# Connexion avec admin + mot de passe admin IPA
```

--- 7H. Résolution DNS ---
```bash
# Vérifier que toutes les entrées DNS sont résolues
for host in ipa01 proxy01 cloud01 mail01 erp01 chat01 pbx01; do
  printf "%-12s → " "$host"
  dig +short ${host}.adlin.lab A @10.10.10.10
done
```

═══════════════════════════════════════════════════════════
ÉTAPE 8 — Vérifications SELinux et sécurité
═══════════════════════════════════════════════════════════

Depuis le bureau :

```bash
cd ~/projects/ADLin
make verify
```

Tous les checks doivent être verts (0 failed).

═══════════════════════════════════════════════════════════
RÉCAPITULATIF DES URLS DE SERVICE
═══════════════════════════════════════════════════════════

| Service     | URL                          |
|-------------|------------------------------|
| FreeIPA     | https://ipa01.adlin.lab      |
| Nextcloud   | https://cloud01.adlin.lab    |
| Webmail     | https://mail01.adlin.lab/SOGo/ |
| Rocket.Chat | https://chat01.adlin.lab     |
| Odoo        | https://erp01.adlin.lab      |
| FreePBX     | https://pbx01.adlin.lab/admin/ |
| Proxy       | https://proxy01.adlin.lab    |

Tous les services utilisent le certificat TLS multi-SAN (6 DNS).
Authentification : FreeIPA (LDAP/Kerberos) pour Nextcloud, SOGo, Rocket.Chat, Odoo.
