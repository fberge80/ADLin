# Procédure d'intégration d'une nouvelle VM dans ADLin

## 1. Proxmox
- [ ] Créer la VM (Rocky Linux 9 ou Debian 12 pour FreePBX)
- [ ] IP statique dans 10.10.10.0/24, enregistrée dans hosts.yml
- [ ] SSH accessible depuis le poste Ansible (clé adlin_ansible)

## 2. Inventaire Ansible
- [ ] Ajouter le FQDN et l'IP dans `inventory/production/hosts.yml`
       dans le bon groupe de service
- [ ] La VM apparaît automatiquement dans `rocky_hosts` si Rocky Linux 9
- [ ] Créer `inventory/production/group_vars/<groupe>.yml` si variables
       spécifiques au service

## 3. DNS FreeIPA
- [ ] Ajouter l'enregistrement A dans FreeIPA :
       `ipa dnsrecord-add adlin.lab <hostname> --a-rec=10.10.10.x`
- [ ] Vérifier la résolution depuis ipa01 : `dig <hostname>.adlin.lab`

## 4. Hardening OS (rôle common)
- [ ] Exécuter `00-common.yml` sur la nouvelle VM :
       `ansible-playbook playbooks/00-common.yml --limit <hostname>`
- [ ] Vérifier SELinux enforcing : `ansible <hostname> -m command -a getenforce`
- [ ] Vérifier l'enrollment IPA : `ansible <hostname> -m command -a "klist -k"`
- [ ] Vérifier NTP : `ansible <hostname> -m command -a "chronyc tracking"`

## 5. Vhost reverse proxy (si service web)
- [ ] Ajouter l'entrée dans `reverse_proxy_vhosts` (defaults ou group_vars)
- [ ] Ajouter l'enregistrement DNS CNAME : `<service>.adlin.lab → proxy01.adlin.lab`
- [ ] Relancer `02-reverse-proxy.yml` avec `--tags vhosts`

## 6. Compte de service LDAP (si intégration FreeIPA)
- [ ] Créer `uid=svc_<service>,cn=sysaccounts,cn=etc,dc=adlin,dc=lab`
       via le rôle freeipa_server ou `ipa` CLI
- [ ] Ajouter le mot de passe dans vault.yml et la référence dans vars.yml
