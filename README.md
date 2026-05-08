# DS-MailArchive — Déploiement

> Fichiers de déploiement public pour **DS-MailArchive** par DataServices  
> Le dépôt principal (code source, CI/CD) est privé.

---

## Installation sur Proxmox VE — One-liner

Depuis le **shell de l'hôte Proxmox**, copiez-collez :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/DataServices-IT/DS-MailArchive-Deploy/main/install-proxmox.sh)"
```

L'installateur crée un **conteneur LXC Debian 12** avec Docker et DS-MailArchive entièrement configuré. Il pose les questions interactivement (IP, storage, port, mot de passe admin…).

**Durée estimée : 3 à 5 minutes.** L'URL d'accès s'affiche en fin d'installation.

---

## Installation manuelle (Debian/Ubuntu/Synology/Raspberry Pi)

```bash
mkdir -p /opt/ds-mailarchive && cd /opt/ds-mailarchive

curl -fsSL https://raw.githubusercontent.com/DataServices-IT/DS-MailArchive-Deploy/main/docker-compose.prod.yml \
     -o docker-compose.yml

curl -fsSL https://raw.githubusercontent.com/DataServices-IT/DS-MailArchive-Deploy/main/.env.example \
     -o .env

# Renseigner les mots de passe
nano .env

docker compose up -d
```

---

## Contenu de ce dépôt

| Fichier | Rôle |
|---|---|
| `install-proxmox.sh` | Script d'installation automatique LXC (Proxmox VE) |
| `docker-compose.prod.yml` | Stack Docker production (4 services, images GHCR) |
| `.env.example` | Template de configuration — à copier en `.env` |

---

## Images Docker (publiques, aucun token requis)

Les images sont hébergées sur GitHub Container Registry :

```
ghcr.io/dataservices-it/ds-mailarchive:latest        # Application
ghcr.io/dataservices-it/ds-mailarchive-nginx:latest  # Reverse proxy + branding
ghcr.io/dataservices-it/ds-mailarchive-backup:latest # Backup automatique
```

Architectures supportées : **linux/amd64** (x86) et **linux/arm64** (Raspberry Pi 4/5).

---

*DataServices © 2026 — contact@dataservices.fr*
