# ADLin — Plan de déploiement

> Ordre chronologique strict, dicté par les dépendances d'authentification.
> **FreeIPA est le socle de tout** : DNS, LDAP et PKI doivent exister avant
> que le moindre service applicatif ne soit installé.

---

## Vue d'ensemble des dépendances

```
                        ┌─────────────────────┐
                        │   PHASE 1           │
                        │   ipa01             │
                        │   FreeIPA Server    │
                        │   DNS · LDAP · PKI  │
                        │   Kerberos · KRA    │
                        └──────────┬──────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │   PHASE 2                   │
                    │   proxy01                   │
                    │   Nginx + TLS               │
                    │   (certmonger / FreeIPA PKI) │
                    └──────────────┬──────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
  ┌───────▼───────┐       ┌────────▼───────┐      ┌────────▼───────┐
  │  PHASE 3a     │       │  PHASE 3b      │      │  PHASE 3c      │
  │  cloud01      │       │  mail01        │      │  chat01        │
  │  Nextcloud 33 │       │  Postfix       │      │  Rocket.Chat   │
  │               │       │  Dovecot       │      │  8.x           │
  │               │       │  SOGo · Rspamd │      │                │
  └───────────────┘       └────────────────┘      └────────────────┘
          │                        │                        │
          └────────────────────────┼────────────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │   PHASE 4                   │
                    │   erp01          pbx01      │
                    │   Odoo 19 CE     FreePBX 17  │
                    │   PostgreSQL     Asterisk 21 │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │   PHASE 5                   │
                    │   Audit SELinux · firewalld  │
                    │   Tests d'intégration        │
                    │   Documentation GitHub       │
                    └─────────────────────────────┘
```

---

## Phase 1 — FreeIPA : le socle obligatoire

> **Pourquoi en premier ?** Tous les services s'authentifient via le LDAP de
> FreeIPA. Sans DNS fonctionnel, les clients ne peuvent pas résoudre
> `ipa01.adlin.lab`. Sans PKI, aucun certificat TLS interne ne peut être émis.
> Sans comptes de service LDAP, aucun service ne peut interroger l'annuaire.

```
VM     : ipa01.adlin.lab — 10.10.10.10
OS     : Rocky Linux 9
vCPUs  : 2 · RAM : 4 Go · Disque : 20 Go
Rôles  : common → freeipa_server
```

### Étapes

- [ ] **1.1** Créer la VM `ipa01` dans Proxmox (Rocky Linux 9, IP statique `10.10.10.10`)
- [ ] **1.2** Vérifier la connectivité SSH depuis le ThinkPad Fedora
  ```bash
  ansible ipa01.adlin.lab -m ping
  ```
- [ ] **1.3** Appliquer le rôle `common` sur `ipa01` (SELinux, EPEL, chrony, firewalld)
  ```bash
  ansible-playbook playbooks/00-common.yml --limit ipa01.adlin.lab
  ```
- [ ] **1.4** Déployer FreeIPA Server via `freeipa.ansible_freeipa.ipaserver`
  ```bash
  ansible-playbook playbooks/01-freeipa-server.yml
  ```
- [ ] **1.5** Vérifier le déploiement FreeIPA
  ```bash
  # Depuis ipa01 :
  ipactl status
  kinit admin
  ipa user-find
  ```
- [ ] **1.6** Créer les comptes de service dans `cn=sysaccounts,cn=etc`

  | Compte de service    | Utilisé par   |
  |----------------------|---------------|
  | `svc_nextcloud`      | Nextcloud      |
  | `svc_mail`           | Postfix/Dovecot/SOGo |
  | `svc_odoo`           | Odoo 19 CE     |
  | `svc_rocketchat`     | Rocket.Chat    |

- [ ] **1.7** Créer les groupes applicatifs FreeIPA
  (`nextcloud_users`, `mail_users`, `odoo_users`, `chat_users`)
- [ ] **1.8** Appliquer le rôle `common` sur **toutes les VM restantes** avec
  `common_ipa_enroll: false` (enrollment activé plus tard)

> **Point de blocage** : les phases 2, 3 et 4 sont toutes bloquées tant que
> cette phase n'est pas entièrement validée.

---

## Phase 2 — Reverse proxy : TLS avant tout

> **Pourquoi avant les services applicatifs ?** Nginx doit être opérationnel
> pour que les vhosts (cloud.adlin.lab, mail.adlin.lab, etc.) répondent dès
> le premier démarrage des services. Les certificats TLS sont émis par
> certmonger via la PKI interne de FreeIPA — `proxy01` doit donc être enrollé
> comme client IPA en premier.

```
VM     : proxy01.adlin.lab — 10.10.10.11
OS     : Rocky Linux 9
vCPUs  : 1 · RAM : 512 Mo · Disque : 10 Go
Rôles  : common (avec ipa_enroll: true) → reverse_proxy
```

### Étapes

- [ ] **2.1** Créer la VM `proxy01` dans Proxmox
- [ ] **2.2** Appliquer le rôle `common` avec `common_ipa_enroll: true`
  (première VM enrollée comme client IPA)
  ```bash
  ansible-playbook playbooks/00-common.yml --limit proxy01.adlin.lab \
    -e "common_ipa_enroll=true"
  ```
- [ ] **2.3** Déployer Nginx + certmonger pour TLS interne (PKI FreeIPA)
  ```bash
  ansible-playbook playbooks/02-reverse-proxy.yml
  ```
- [ ] **2.4** Préparer les vhosts pour les services à venir

  | vhost                   | Backend (port)       |
  |-------------------------|----------------------|
  | `cloud.adlin.lab`       | `cloud01:443`        |
  | `mail.adlin.lab`        | `mail01:443`         |
  | `erp.adlin.lab`         | `erp01:8069`         |
  | `chat.adlin.lab`        | `chat01:3000`        |
  | `pbx.adlin.lab`         | `pbx01:443`          |

- [ ] **2.5** Vérifier que les vhosts répondent (même avec une page 502 temporaire)

> **Décision PKI** : la PKI interne FreeIPA (Dogtag via certmonger) est
> préférable à Let's Encrypt pour un lab isolé sur `vmbr1`. Let's Encrypt
> nécessite un accès internet et un domaine public, ce qui complique
> l'architecture sans bénéfice pour un portfolio.

---

## Phase 3 — Services de productivité (parallélisables)

> **Pourquoi ces trois ensemble ?** Nextcloud, la stack mail et Rocket.Chat
> dépendent tous uniquement de FreeIPA (phase 1) et du reverse proxy (phase 2).
> Ils n'ont aucune dépendance entre eux et peuvent être déployés en parallèle
> ou dans l'ordre qui convient.

---

### Phase 3a — Nextcloud 33

```
VM     : cloud01.adlin.lab — 10.10.10.13
OS     : Rocky Linux 9
vCPUs  : 2 · RAM : 4 Go · Disque : 100+ Go
Rôles  : common (ipa_enroll: true) → nextcloud
```

#### Étapes

- [ ] **3a.1** Créer la VM `cloud01` dans Proxmox
- [ ] **3a.2** Appliquer `common` avec enrollment IPA
- [ ] **3a.3** Déployer Nextcloud via le rôle `nextcloud`
  ```bash
  ansible-playbook playbooks/03-nextcloud.yml
  ```
- [ ] **3a.4** Configurer l'app `user_ldap` — paramètre critique :
  ```
  UUID override : ipaUniqueID  ← sans ça, les comptes se dupliquent
  ```
- [ ] **3a.5** Tester la connexion d'un utilisateur FreeIPA sur `cloud.adlin.lab`

---

### Phase 3b — Stack mail (Postfix + Dovecot + SOGo + Rspamd)

```
VM     : mail01.adlin.lab — 10.10.10.12
OS     : Rocky Linux 9
vCPUs  : 2 · RAM : 3 Go · Disque : 50 Go
Rôles  : common (ipa_enroll: true) → mailserver
```

#### Étapes

- [ ] **3b.1** Créer la VM `mail01` dans Proxmox
- [ ] **3b.2** Appliquer `common` avec enrollment IPA
- [ ] **3b.3** Étendre le schéma FreeIPA avec les attributs mail
  (plugin `freeipa-mailserver` / tâche `freeipa_schema.yml`)
- [ ] **3b.4** Déployer la stack mail via le rôle `mailserver`
  ```bash
  ansible-playbook playbooks/04-mailserver.yml
  ```
- [ ] **3b.5** Valider l'envoi et la réception d'un mail de test
- [ ] **3b.6** Tester la synchronisation ActiveSync (mobile)

> **Complexité** : c'est le rôle le plus complexe du projet — quatre composants
> (Postfix, Dovecot, SOGo, Rspamd) avec des intégrations LDAP distinctes.
> Prévoir plus de temps de débogage.

---

### Phase 3c — Rocket.Chat 8.x

```
VM     : chat01.adlin.lab — 10.10.10.15
OS     : Rocky Linux 9
vCPUs  : 1 · RAM : 2 Go · Disque : 30 Go
Rôles  : common (ipa_enroll: true) → rocketchat (Docker Compose)
```

#### Étapes

- [ ] **3c.1** Créer la VM `chat01` dans Proxmox
- [ ] **3c.2** Appliquer `common` avec enrollment IPA
- [ ] **3c.3** Déployer Rocket.Chat + MongoDB via Docker Compose
  ```bash
  ansible-playbook playbooks/06-rocketchat.yml
  ```
- [ ] **3c.4** Configurer LDAP FreeIPA (sync groupes inclus, gratuit en Community)
- [ ] **3c.5** Vérifier la connexion depuis `chat.adlin.lab`

> **Point de vigilance** : les workspaces Community passent en lecture seule
> après 90 jours sans validation en ligne. Prévoir un accès internet sortant
> depuis `chat01` ou accepter cette limitation pour un lab.

---

## Phase 4 — Services métier

> **Pourquoi après la phase 3 ?** Odoo et FreePBX sont fonctionnellement
> indépendants des autres services (pas de dépendance croisée), mais ils sont
> plus complexes à déployer. Les traiter après avoir validé les phases
> précédentes réduit la surface de débogage simultanée.

---

### Phase 4a — Odoo 19 Community Edition

```
VM     : erp01.adlin.lab — 10.10.10.14
OS     : Rocky Linux 9
vCPUs  : 2-4 · RAM : 4 Go · Disque : 50 Go
Rôles  : common (ipa_enroll: true) → odoo
```

#### Étapes

- [ ] **4a.1** Créer la VM `erp01` dans Proxmox
- [ ] **4a.2** Appliquer `common` avec enrollment IPA
- [ ] **4a.3** Compiler Python 3.10+ si nécessaire (Rocky 9 fournit Python 3.9)
- [ ] **4a.4** Déployer Odoo + PostgreSQL via le rôle `odoo`
  ```bash
  ansible-playbook playbooks/05-odoo.yml
  ```
- [ ] **4a.5** Activer le module `auth_ldap` et configurer FreeIPA
- [ ] **4a.6** Tester la création automatique d'utilisateur au premier login LDAP

> **Limitation connue** : pas de synchronisation FreeIPA → rôles Odoo.
> L'affectation des droits reste manuelle dans Odoo. C'est une contrainte
> de l'édition Community, non un bug de configuration.

---

### Phase 4b — FreePBX 17 / Asterisk 21

```
VM     : pbx01.adlin.lab — 10.10.10.16
OS     : Debian 12  ← exception obligatoire (Sangoma a abandonné RHEL en 2024)
vCPUs  : 1 · RAM : 1,5 Go · Disque : 20 Go
Rôles  : freepbx (rôle custom Debian)
```

#### Étapes

- [ ] **4b.1** Créer la VM `pbx01` dans Proxmox avec **Debian 12** (pas Rocky Linux)
- [ ] **4b.2** Enrollée comme client FreeIPA pour la gestion SSH/sudo centralisée
  (l'authentification SIP reste locale — FreePBX n'a pas d'intégration LDAP native)
- [ ] **4b.3** Déployer FreePBX 17 + Asterisk 21 via le rôle `freepbx`
  ```bash
  ansible-playbook playbooks/07-freepbx.yml
  ```
- [ ] **4b.4** Configurer le trunk SIP (OVH Telecom, Keyyo, etc.)
- [ ] **4b.5** Créer les extensions, IVR, files d'attente

> **Note SELinux** : FreePBX tourne avec SELinux en mode **permissif** sur
> Debian (pas de policy adaptée). C'est la seule VM du projet dans ce cas.
> Ce choix est documenté et justifié dans le README.

---

## Phase 5 — Sécurisation et documentation

> **Pourquoi en dernier ?** L'audit SELinux et firewalld ne peut être réalisé
> qu'une fois tous les services déployés et testés. Les booleans et contextes
> SELinux définitifs dépendent du comportement réel de chaque service.

### Étapes

- [ ] **5.1** Audit SELinux sur toutes les VM Rocky Linux 9
  ```bash
  # Vérifier le mode enforcing sur toutes les VM Rocky Linux
  ansible rocky_hosts -m command -a "getenforce"

  # Chercher les denials récents dans les logs
  ansible rocky_hosts -m command -a "ausearch -m avc -ts recent"
  ```
- [ ] **5.2** Audit firewalld — valider que seuls les ports nécessaires sont ouverts

  | VM       | Ports ouverts                                           |
  |----------|---------------------------------------------------------|
  | ipa01    | 80, 443, 389, 636, 88, 464 (tcp/udp), 53 (tcp/udp)     |
  | proxy01  | 80, 443                                                 |
  | cloud01  | 443 (interne proxy uniquement)                          |
  | mail01   | 25, 465, 587, 143, 993, 4190, 443                       |
  | erp01    | 8069, 8072 (interne proxy uniquement)                   |
  | chat01   | 3000 (interne proxy uniquement)                         |
  | pbx01    | 5060/udp, 5061/tcp, 10000-20000/udp, 443                |

- [ ] **5.3** Test d'intégration FreeIPA → tous les services
  ```bash
  ansible-playbook playbooks/verify.yml --vault-password-file .vault_pass
  ```
  Scénario de test : créer un utilisateur dans FreeIPA, vérifier sa propagation
  vers Nextcloud, SOGo, Odoo et Rocket.Chat.
- [ ] **5.4** Mettre à jour `common_ntp_servers` pour pointer vers `ipa01.adlin.lab`
  et ré-appliquer le rôle `common` sur toutes les VM (phase NTP post-FreeIPA)
- [ ] **5.5** Finaliser le README.md GitHub avec diagramme d'architecture et
  captures d'écran des interfaces

---

## Résumé des commandes de déploiement

```bash
# Déploiement complet dans l'ordre (respecte les dépendances)
make deploy-common      # Phase 1a : hardening OS toutes VM (sans enrollment IPA)
make deploy-freeipa     # Phase 1b : FreeIPA Server sur ipa01
make deploy-proxy       # Phase 2  : Nginx + TLS sur proxy01
make deploy-nextcloud   # Phase 3a : Nextcloud sur cloud01
make deploy-mail        # Phase 3b : stack mail sur mail01
make deploy-rocketchat  # Phase 3c : Rocket.Chat sur chat01
make deploy-odoo        # Phase 4a : Odoo 19 CE sur erp01
make deploy-freepbx     # Phase 4b : FreePBX 17 sur pbx01

# Ou déploiement complet en une commande (après avoir validé phase 1 et 2)
ansible-playbook playbooks/site.yml --vault-password-file .vault_pass
```

---

## Chronologie estimée

```
Semaine 1    │████████████████│ Phase 1 (FreeIPA) + Phase 2 (proxy)
Semaine 2    │████████████████│ Phase 3 (Nextcloud + Mail + Rocket.Chat)
Semaine 3    │████████████████│ Phase 4 (Odoo + FreePBX)
Semaine 4    │████████████████│ Phase 5 (audit + doc + tests intégration)
```

> Les estimations supposent que chaque rôle Ansible est développé et testé
> au fur et à mesure — pas uniquement exécuté. Le rôle `mailserver` (4 composants)
> est le plus chronophage de la phase 3.

---

*Généré pour le projet [ADLin](https://github.com/fberge80/ADLin) —
Infrastructure PME open-source sur Proxmox VE*
