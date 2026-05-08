#!/usr/bin/env bash
# ============================================================
#  DS-MailArchive — Installateur LXC pour Proxmox VE
#  DataServices © 2026
#
#  Depuis le shell de l'hôte Proxmox VE :
#  bash -c "$(curl -fsSL https://raw.githubusercontent.com/DataServices-IT/DS-MailArchive/main/install-proxmox.sh)"
# ============================================================

set -Eeuo pipefail

# ── COULEURS ET STYLES ────────────────────────────────────
YW="\033[33m"
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
GY="\033[0;37m"
CL="\033[m"
BOLD="\033[1m"
BFR="\\r\\033[K"

# ── FONCTIONS D'AFFICHAGE ─────────────────────────────────
spin() {
  local pid=$1 msg="$2"
  local sp='⣾⣽⣻⢿⡿⣟⣯⣷'
  while kill -0 "$pid" 2>/dev/null; do
    for i in 0 1 2 3 4 5 6 7; do
      printf "\r   ${YW}${sp:$i:1}${CL}  %s..." "$msg"
      sleep 0.12
    done
  done
  printf "${BFR}"
}

msg_info()  { printf "   ${BL}◈${CL}  %s...\n" "$1"; }
msg_ok()    { printf "   ${GN}✔${CL}  %s\n"   "$1"; }
msg_warn()  { printf "   ${YW}⚠${CL}  %s\n"   "$1"; }
msg_error() { printf "\n   ${RD}✗${CL}  ${BOLD}ERREUR :${CL} %s\n\n" "$1"; exit 1; }

ask() {
  local prompt="$1" default="$2"
  printf "   ${YW}?${CL}  ${BOLD}%-35s${CL} [${GY}%s${CL}] : " "$prompt" "$default"
  read -r val
  printf '%s' "${val:-$default}"
}

ask_secret() {
  local prompt="$1"
  printf "   ${YW}?${CL}  ${BOLD}%-35s${CL} : " "$prompt"
  read -rs val
  printf '\n'
  printf '%s' "$val"
}

trap 'msg_error "Installation interrompue à la ligne $LINENO."' ERR

# ── VÉRIFICATION PROXMOX ──────────────────────────────────
if ! command -v pct &>/dev/null; then
  msg_error "Ce script doit être exécuté directement sur un hôte Proxmox VE."
fi
if [[ $EUID -ne 0 ]]; then
  msg_error "Ce script doit être exécuté en tant que root."
fi

# ── HEADER ────────────────────────────────────────────────
clear
printf "\n"
printf "  ${RD}${BOLD}╔══════════════════════════════════════════════════╗${CL}\n"
printf "  ${RD}${BOLD}║                                                  ║${CL}\n"
printf "  ${RD}${BOLD}║   ██████╗ ███████╗    ███╗   ███╗ █████╗        ║${CL}\n"
printf "  ${RD}${BOLD}║   ██╔══██╗██╔════╝    ████╗ ████║██╔══██╗       ║${CL}\n"
printf "  ${RD}${BOLD}║   ██║  ██║███████╗    ██╔████╔██║███████║       ║${CL}\n"
printf "  ${RD}${BOLD}║   ██║  ██║╚════██║    ██║╚██╔╝██║██╔══██║       ║${CL}\n"
printf "  ${RD}${BOLD}║   ██████╔╝███████║    ██║ ╚═╝ ██║██║  ██║       ║${CL}\n"
printf "  ${RD}${BOLD}║   ╚═════╝ ╚══════╝    ╚═╝     ╚═╝╚═╝  ╚═╝       ║${CL}\n"
printf "  ${RD}${BOLD}║                                                  ║${CL}\n"
printf "  ${RD}${BOLD}║         DS-MailArchive  ·  Installateur LXC      ║${CL}\n"
printf "  ${RD}${BOLD}║         DataServices  ·  Proxmox VE              ║${CL}\n"
printf "  ${RD}${BOLD}╚══════════════════════════════════════════════════╝${CL}\n"
printf "\n"

# ── DÉTECTION CTID SUIVANT ────────────────────────────────
NEXT_ID=$(pvesh get /cluster/nextid 2>/dev/null || echo "200")

# ── LISTE DES STORAGES DISPONIBLES ───────────────────────
printf "  ${BL}${BOLD}Storages disponibles sur cet hôte :${CL}\n"
STORAGES=()
while IFS= read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  type=$(echo "$line" | awk '{print $2}')
  avail=$(echo "$line" | awk '{print $5}')
  printf "    ${GY}•${CL} %-20s %s\n" "$name" "(${type})"
  STORAGES+=("$name")
done < <(pvesm status --content rootdir 2>/dev/null | tail -n +2)
printf "\n"

# ── LISTE DES BRIDGES RÉSEAU ─────────────────────────────
printf "  ${BL}${BOLD}Bridges réseau disponibles :${CL}\n"
ip link show | grep -oP '(?<=^\d+: )vmbr\w+' 2>/dev/null | while read -r br; do
  printf "    ${GY}•${CL} %s\n" "$br"
done || true
printf "\n"

# ── PROMPTS INTERACTIFS ───────────────────────────────────
printf "  ${BOLD}━━━━━━━━━━━━━━━━━━  Conteneur LXC  ━━━━━━━━━━━━━━━━━━${CL}\n\n"

CT_ID=$(ask      "ID du conteneur"                  "$NEXT_ID")
HOSTNAME=$(ask   "Nom d'hôte du conteneur"          "ds-mailarchive")
CT_IP=$(ask      "Adresse IP (format CIDR)"         "192.168.1.100/24")
CT_GW=$(ask      "Passerelle (gateway)"             "192.168.1.1")
CT_DNS=$(ask     "Serveur DNS"                      "8.8.8.8")
CT_BRIDGE=$(ask  "Bridge réseau"                    "vmbr0")
CT_STORAGE=$(ask "Storage Proxmox"                  "${STORAGES[0]:-local-lvm}")
CT_DISK=$(ask    "Taille du disque (Go)"            "100")
CT_RAM=$(ask     "RAM allouée (Mo)"                 "2048")
CT_CORES=$(ask   "Nombre de cœurs CPU"              "2")

printf "\n  ${BOLD}━━━━━━━━━━━━━━━━━━  Application  ━━━━━━━━━━━━━━━━━━━━${CL}\n\n"

APP_PORT=$(ask   "Port HTTP de l'interface web"     "80")
ADMIN_USER=$(ask "Nom d'utilisateur administrateur" "admin")
TIMEZONE=$(ask   "Fuseau horaire"                   "Europe/Paris")

printf "\n"
while true; do
  ADMIN_PASS=$(ask_secret "Mot de passe administrateur")
  if [[ -z "$ADMIN_PASS" ]]; then
    printf "   ${RD}Le mot de passe ne peut pas être vide.${CL}\n"
    continue
  fi
  ADMIN_PASS2=$(ask_secret "Confirmer le mot de passe")
  if [[ "$ADMIN_PASS" == "$ADMIN_PASS2" ]]; then
    break
  fi
  printf "   ${RD}Les mots de passe ne correspondent pas, recommencez.${CL}\n\n"
done

# Mot de passe BDD généré automatiquement (alphanumérique, sans ambiguïté)
DB_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | tr -d 'lIO0' | head -c 32)

# IP sans le masque (pour affichage et Health Check)
CT_IP_ONLY="${CT_IP%%/*}"

# ── RÉSUMÉ AVANT LANCEMENT ────────────────────────────────
printf "\n"
printf "  ${BOLD}━━━━━━━━━━━━━━━━━━  Récapitulatif  ━━━━━━━━━━━━━━━━━━${CL}\n\n"
printf "   ${GY}CT ID         :${CL} ${BOLD}%s${CL}\n"            "$CT_ID"
printf "   ${GY}Hostname      :${CL} ${BOLD}%s${CL}\n"            "$HOSTNAME"
printf "   ${GY}Adresse IP    :${CL} ${BOLD}%s${CL}  (GW: %s)\n" "$CT_IP" "$CT_GW"
printf "   ${GY}DNS           :${CL} ${BOLD}%s${CL}\n"            "$CT_DNS"
printf "   ${GY}Bridge        :${CL} ${BOLD}%s${CL}\n"            "$CT_BRIDGE"
printf "   ${GY}Storage       :${CL} ${BOLD}%s${CL}\n"            "$CT_STORAGE"
printf "   ${GY}Disque        :${CL} ${BOLD}%s Go${CL}\n"         "$CT_DISK"
printf "   ${GY}RAM           :${CL} ${BOLD}%s Mo${CL}\n"         "$CT_RAM"
printf "   ${GY}CPU           :${CL} ${BOLD}%s cœur(s)${CL}\n"    "$CT_CORES"
printf "   ${GY}Port HTTP     :${CL} ${BOLD}%s${CL}\n"            "$APP_PORT"
printf "   ${GY}Admin user    :${CL} ${BOLD}%s${CL}\n"            "$ADMIN_USER"
printf "   ${GY}Fuseau        :${CL} ${BOLD}%s${CL}\n"            "$TIMEZONE"
printf "   ${GY}URL finale    :${CL} ${BOLD}http://%s:%s/${CL}\n" "$CT_IP_ONLY" "$APP_PORT"
printf "\n"

printf "   ${YW}?${CL}  ${BOLD}Lancer l'installation ?${CL} [${GY}O${CL}/n] : "
read -r confirm
case "${confirm,,}" in
  n|no|non) printf "\n   Installation annulée.\n\n"; exit 0 ;;
esac
printf "\n"

# ══════════════════════════════════════════════════════════
# INSTALLATION
# ══════════════════════════════════════════════════════════

# ── TEMPLATE DEBIAN 12 ────────────────────────────────────
msg_info "Recherche du template Debian 12"
TEMPLATE_PATH=$(pveam list local 2>/dev/null | grep "debian-12-standard" | awk '{print $1}' | tail -1)

if [[ -z "$TEMPLATE_PATH" ]]; then
  msg_warn "Template non trouvé localement — téléchargement en cours"
  TEMPLATE_NAME=$(pveam available --section system 2>/dev/null | grep "debian-12-standard" | awk '{print $2}' | tail -1)
  if [[ -z "$TEMPLATE_NAME" ]]; then
    msg_error "Impossible de trouver le template Debian 12. Vérifiez la connectivité."
  fi
  pveam download local "$TEMPLATE_NAME" &>/dev/null &
  spin $! "Téléchargement de $TEMPLATE_NAME"
  wait $!
  TEMPLATE_PATH="local:vztmpl/${TEMPLATE_NAME}"
fi
msg_ok "Template Debian 12 : $TEMPLATE_PATH"

# ── CRÉATION DU LXC ───────────────────────────────────────
msg_info "Création du conteneur CT${CT_ID}"
CT_ROOT_PASS=$(tr -dc 'A-Za-z0-9@#%-' </dev/urandom | head -c 24)

pct create "$CT_ID" "$TEMPLATE_PATH" \
  --hostname    "$HOSTNAME"           \
  --password    "$CT_ROOT_PASS"       \
  --cores       "$CT_CORES"           \
  --memory      "$CT_RAM"             \
  --swap        512                   \
  --rootfs      "${CT_STORAGE}:${CT_DISK}" \
  --net0        "name=eth0,bridge=${CT_BRIDGE},ip=${CT_IP},gw=${CT_GW}" \
  --nameserver  "$CT_DNS"             \
  --unprivileged 1                    \
  --features    "nesting=1"           \
  --ostype      debian                \
  --start       0                     \
  &>/dev/null

msg_ok "Conteneur CT${CT_ID} créé"

# ── DÉMARRAGE ─────────────────────────────────────────────
msg_info "Démarrage du conteneur"
pct start "$CT_ID" &>/dev/null

# Attendre que le réseau soit prêt dans le conteneur
for i in $(seq 1 30); do
  if pct exec "$CT_ID" -- bash -c "ping -c1 -W2 8.8.8.8 &>/dev/null"; then
    break
  fi
  sleep 3
done
msg_ok "Conteneur démarré et réseau actif"

# ── MISE À JOUR SYSTÈME ───────────────────────────────────
pct exec "$CT_ID" -- bash -c "
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get upgrade -y -qq
  apt-get install -y -qq curl ca-certificates
" &>/dev/null &
spin $! "Mise à jour du système (apt)"
wait $!
msg_ok "Système mis à jour"

# ── INSTALLATION DOCKER ───────────────────────────────────
pct exec "$CT_ID" -- bash -c "
  curl -fsSL https://get.docker.com | sh
" &>/dev/null &
spin $! "Installation de Docker"
wait $!
msg_ok "Docker installé"

# ── PRÉPARATION DES FICHIERS DE CONFIGURATION ─────────────
# .env : écrit ligne par ligne avec printf pour gérer les caractères spéciaux
ENV_TMP=$(mktemp)
printf 'DB_PASSWORD=%s\n'       "$DB_PASS"    >  "$ENV_TMP"
printf 'ADMIN_USER=%s\n'        "$ADMIN_USER" >> "$ENV_TMP"
printf 'ADMIN_PASSWORD=%s\n'    "$ADMIN_PASS" >> "$ENV_TMP"
printf 'APP_PORT=%s\n'          "$APP_PORT"   >> "$ENV_TMP"
printf 'TIMEZONE=%s\n'          "$TIMEZONE"   >> "$ENV_TMP"
printf 'SYNC_INTERVAL=15\n'                   >> "$ENV_TMP"
printf 'BACKUP_KEEP_DAYS=30\n'                >> "$ENV_TMP"

# Script de setup à exécuter à l'intérieur du CT (sans expansion de variables)
SETUP_TMP=$(mktemp)
cat > "$SETUP_TMP" << 'SETUP_SCRIPT'
#!/usr/bin/env bash
set -e
mkdir -p /opt/ds-mailarchive
cd /opt/ds-mailarchive
curl -fsSL \
  https://raw.githubusercontent.com/DataServices-IT/DS-MailArchive/main/docker-compose.prod.yml \
  -o docker-compose.yml
chmod 600 .env
docker compose pull
docker compose up -d
SETUP_SCRIPT
chmod +x "$SETUP_TMP"

# Pousser les fichiers dans le conteneur
pct exec "$CT_ID" -- mkdir -p /opt/ds-mailarchive
pct push "$CT_ID" "$ENV_TMP"   /opt/ds-mailarchive/.env
pct push "$CT_ID" "$SETUP_TMP" /root/setup-ds-mailarchive.sh

rm -f "$ENV_TMP" "$SETUP_TMP"

# ── DÉPLOIEMENT DE LA STACK ───────────────────────────────
pct exec "$CT_ID" -- bash /root/setup-ds-mailarchive.sh &>/dev/null &
spin $! "Téléchargement des images et démarrage de la stack"
wait $!
msg_ok "Stack DS-MailArchive déployée"

# ── ATTENTE DE DISPONIBILITÉ ──────────────────────────────
msg_info "Attente du démarrage de l'application"
READY=0
for i in $(seq 1 40); do
  if pct exec "$CT_ID" -- bash -c "curl -sf http://localhost:${APP_PORT}/ -o /dev/null 2>/dev/null"; then
    READY=1
    break
  fi
  sleep 5
done

if [[ $READY -eq 1 ]]; then
  msg_ok "Application accessible"
else
  msg_warn "L'application met peut-être plus de temps à démarrer (première initialisation de la base)"
  printf "   ${GY}Vérifiez avec :${CL} pct exec %s -- docker compose -f /opt/ds-mailarchive/docker-compose.yml logs\n" "$CT_ID"
fi

# Nettoyage du script interne
pct exec "$CT_ID" -- rm -f /root/setup-ds-mailarchive.sh &>/dev/null || true

# ══════════════════════════════════════════════════════════
# RÉSUMÉ FINAL
# ══════════════════════════════════════════════════════════
printf "\n"
printf "  ${GN}${BOLD}╔══════════════════════════════════════════════════╗${CL}\n"
printf "  ${GN}${BOLD}║   ✔  Installation terminée avec succès !         ║${CL}\n"
printf "  ${GN}${BOLD}╠══════════════════════════════════════════════════╣${CL}\n"
printf "  ${GN}${BOLD}║${CL}                                                  ${GN}${BOLD}║${CL}\n"
printf "  ${GN}${BOLD}║${CL}   ${BOLD}URL         :${CL} http://%-26s${GN}${BOLD}║${CL}\n" "${CT_IP_ONLY}:${APP_PORT}/"
printf "  ${GN}${BOLD}║${CL}   ${BOLD}Utilisateur :${CL} %-30s${GN}${BOLD}║${CL}\n" "$ADMIN_USER"
printf "  ${GN}${BOLD}║${CL}   ${BOLD}Mot de passe:${CL} %-30s${GN}${BOLD}║${CL}\n" "(celui que vous avez saisi)"
printf "  ${GN}${BOLD}║${CL}   ${BOLD}Dossier     :${CL} %-30s${GN}${BOLD}║${CL}\n" "/opt/ds-mailarchive/"
printf "  ${GN}${BOLD}║${CL}   ${BOLD}CT ID       :${CL} %-30s${GN}${BOLD}║${CL}\n" "$CT_ID"
printf "  ${GN}${BOLD}║${CL}                                                  ${GN}${BOLD}║${CL}\n"
printf "  ${GN}${BOLD}╚══════════════════════════════════════════════════╝${CL}\n"
printf "\n"
printf "  ${BOLD}Commandes utiles :${CL}\n"
printf "   ${GY}•${CL} Accéder au CT         : ${BOLD}pct enter %s${CL}\n"                        "$CT_ID"
printf "   ${GY}•${CL} Voir les logs         : ${BOLD}pct exec %s -- docker compose -f /opt/ds-mailarchive/docker-compose.yml logs -f${CL}\n" "$CT_ID"
printf "   ${GY}•${CL} Statut des services   : ${BOLD}pct exec %s -- docker compose -f /opt/ds-mailarchive/docker-compose.yml ps${CL}\n"    "$CT_ID"
printf "   ${GY}•${CL} Mettre à jour         : ${BOLD}pct exec %s -- docker compose -f /opt/ds-mailarchive/docker-compose.yml pull && docker compose -f /opt/ds-mailarchive/docker-compose.yml up -d${CL}\n" "$CT_ID"
printf "   ${GY}•${CL} Arrêter               : ${BOLD}pct exec %s -- docker compose -f /opt/ds-mailarchive/docker-compose.yml down${CL}\n"  "$CT_ID"
printf "\n"
