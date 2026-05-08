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

# Stocke la réponse dans REPLY_VAL — NE PAS appeler via $() sinon sous-shell
REPLY_VAL=""
ask() {
  local prompt="$1" default="$2"
  printf "   ${YW}?${CL}  ${BOLD}%-35s${CL} [${GY}%s${CL}] : " "$prompt" "$default"
  IFS= read -r REPLY_VAL
  REPLY_VAL="${REPLY_VAL:-$default}"
}

REPLY_SECRET=""
ask_secret() {
  local prompt="$1"
  printf "   ${YW}?${CL}  ${BOLD}%-35s${CL} : " "$prompt"
  IFS= read -rs REPLY_SECRET
  printf '\n'
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

# ── LISTE DES BRIDGES RÉSEAU (numérotée) ─────────────────
BRIDGES=()
printf "  ${BL}${BOLD}Bridges réseau disponibles :${CL}\n"
while IFS= read -r br; do
  printf "    ${GY}[%s]${CL} %s\n" "$((${#BRIDGES[@]}+1))" "$br"
  BRIDGES+=("$br")
done < <(ip link show 2>/dev/null | grep -oP '(?<=^\d+: )vmbr\w+')
[[ ${#BRIDGES[@]} -eq 0 ]] && BRIDGES=("vmbr0")
printf "\n"

# ── LISTE DES STORAGES DISPONIBLES (numérotée) ───────────
STORAGES=()
printf "  ${BL}${BOLD}Storages disponibles sur cet hôte :${CL}\n"
while IFS= read -r line; do
  s_name=$(echo "$line" | awk '{print $1}')
  s_type=$(echo "$line" | awk '{print $2}')
  printf "    ${GY}[%s]${CL} %-20s %s\n" "$((${#STORAGES[@]}+1))" "$s_name" "(${s_type})"
  STORAGES+=("$s_name")
done < <(pvesm status --content rootdir 2>/dev/null | tail -n +2)
[[ ${#STORAGES[@]} -eq 0 ]] && STORAGES=("local-lvm")
printf "\n"

# ── PROMPTS INTERACTIFS ───────────────────────────────────
printf "  ${BOLD}━━━━━━━━━━━━━━━━━━  Conteneur LXC  ━━━━━━━━━━━━━━━━━━${CL}\n\n"

ask "ID du conteneur"         "$NEXT_ID"       ; CT_ID="$REPLY_VAL"
ask "Nom d'hôte du conteneur" "ds-mailarchive" ; HOSTNAME="$REPLY_VAL"

# ── BRIDGE RÉSEAU ────────────────────────────────────────
if [[ ${#BRIDGES[@]} -eq 1 ]]; then
  CT_BRIDGE="${BRIDGES[0]}"
  printf "   ${GN}✔${CL}  Bridge réseau : ${BOLD}%s${CL} (seul bridge disponible)\n" "$CT_BRIDGE"
else
  printf "   ${YW}?${CL}  ${BOLD}%-35s${CL} [${GY}1${CL}] : " "Bridge réseau (numéro)"
  IFS= read -r _bc ; _bc="${_bc:-1}"
  CT_BRIDGE="${BRIDGES[$((_bc-1))]:-${BRIDGES[0]}}"
fi

# ── DÉTECTION IP DU BRIDGE (defaults intelligents) ───────
BRIDGE_CIDR=$(ip addr show "$CT_BRIDGE" 2>/dev/null | awk '/inet /{print $2; exit}')
if [[ -n "$BRIDGE_CIDR" ]]; then
  _gw="${BRIDGE_CIDR%%/*}"
  _prefix="${BRIDGE_CIDR##*/}"
  _net=$(echo "$_gw" | cut -d. -f1-3)
  DEFAULT_GW="$_gw"
  DEFAULT_IP="${_net}.200/${_prefix}"
  DEFAULT_DNS="$_gw"
else
  DEFAULT_GW="192.168.1.1"
  DEFAULT_IP="192.168.1.200/24"
  DEFAULT_DNS="8.8.8.8"
fi

# ── MODE RÉSEAU : DHCP OU IP STATIQUE ────────────────────
printf "\n"
printf "   ${YW}?${CL}  ${BOLD}Configuration réseau du conteneur :${CL}\n"
printf "       ${GY}[1]${CL} DHCP    — adresse IP automatique ${GY}(défaut)${CL}\n"
printf "       ${GY}[2]${CL} Statique — adresse IP fixe\n"
printf "   ${YW}?${CL}  ${BOLD}Votre choix${CL} [${GY}1${CL}] : "
IFS= read -r _nc ; _nc="${_nc:-1}"

if [[ "$_nc" == "2" ]]; then
  CT_NET_MODE="static"
  printf "\n"
  ask "Adresse IP du conteneur (CIDR)" "$DEFAULT_IP" ; CT_IP="$REPLY_VAL"
  ask "Passerelle (gateway)"           "$DEFAULT_GW" ; CT_GW="$REPLY_VAL"
  ask "Serveur DNS"                    "$DEFAULT_DNS" ; CT_DNS="$REPLY_VAL"
else
  CT_NET_MODE="dhcp"
  CT_IP="dhcp"
  CT_GW=""
  CT_DNS="$DEFAULT_DNS"
  printf "   ${GN}✔${CL}  Réseau DHCP — adresse assignée automatiquement\n"
fi

# ── STORAGE (choix numéroté) ──────────────────────────────
printf "\n"
if [[ ${#STORAGES[@]} -eq 1 ]]; then
  CT_STORAGE="${STORAGES[0]}"
  printf "   ${GN}✔${CL}  Storage : ${BOLD}%s${CL} (seul storage disponible)\n" "$CT_STORAGE"
else
  printf "   ${YW}?${CL}  ${BOLD}%-35s${CL} [${GY}1${CL}] : " "Storage Proxmox (numéro)"
  IFS= read -r _sc ; _sc="${_sc:-1}"
  CT_STORAGE="${STORAGES[$((_sc-1))]:-${STORAGES[0]}}"
fi

ask "Taille du disque (Go)"   "100"  ; CT_DISK="$REPLY_VAL"
ask "RAM allouée (Mo)"        "2048" ; CT_RAM="$REPLY_VAL"
ask "Nombre de cœurs CPU"     "2"    ; CT_CORES="$REPLY_VAL"

printf "\n  ${BOLD}━━━━━━━━━━━━━━━━━━  Application  ━━━━━━━━━━━━━━━━━━━━${CL}\n\n"

ask "Port HTTP de l'interface web"     "80"            ; APP_PORT="$REPLY_VAL"
ask "Nom d'utilisateur administrateur" "admin"         ; ADMIN_USER="$REPLY_VAL"
ask "Fuseau horaire"                   "Europe/Paris"  ; TIMEZONE="$REPLY_VAL"

printf "\n"
while true; do
  ask_secret "Mot de passe administrateur"  ; ADMIN_PASS="$REPLY_SECRET"
  if [[ -z "$ADMIN_PASS" ]]; then
    printf "   ${RD}Le mot de passe ne peut pas être vide.${CL}\n"
    continue
  fi
  ask_secret "Confirmer le mot de passe"    ; ADMIN_PASS2="$REPLY_SECRET"
  if [[ "$ADMIN_PASS" == "$ADMIN_PASS2" ]]; then
    break
  fi
  printf "   ${RD}Les mots de passe ne correspondent pas, recommencez.${CL}\n\n"
done

# Mot de passe BDD généré automatiquement (alphanumérique, sans ambiguïté)
# set +o pipefail : head -c coupe le pipe de tr → SIGPIPE 141 sinon avec set -o pipefail
set +o pipefail
DB_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | tr -d 'lIO0' | head -c 32)
set -o pipefail

# IP sans le masque — pour DHCP on détecte après démarrage du CT
CT_IP_ONLY="${CT_IP%%/*}"
[[ "$CT_NET_MODE" == "dhcp" ]] && CT_IP_ONLY="dhcp"

# ── RÉSUMÉ AVANT LANCEMENT ────────────────────────────────
printf "\n"
printf "  ${BOLD}━━━━━━━━━━━━━━━━━━  Récapitulatif  ━━━━━━━━━━━━━━━━━━${CL}\n\n"
printf "   ${GY}CT ID         :${CL} ${BOLD}%s${CL}\n"            "$CT_ID"
printf "   ${GY}Hostname      :${CL} ${BOLD}%s${CL}\n"            "$HOSTNAME"
if [[ "$CT_NET_MODE" == "dhcp" ]]; then
  printf "   ${GY}Réseau        :${CL} ${BOLD}DHCP (IP automatique via %s)${CL}\n" "$CT_BRIDGE"
else
  printf "   ${GY}Adresse IP    :${CL} ${BOLD}%s${CL}  (GW: %s)\n" "$CT_IP" "$CT_GW"
fi
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
IFS= read -r confirm
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
set +o pipefail
CT_ROOT_PASS=$(tr -dc 'A-Za-z0-9@#%-' </dev/urandom | head -c 24)
set -o pipefail

pct create "$CT_ID" "$TEMPLATE_PATH" \
  --hostname    "$HOSTNAME"           \
  --password    "$CT_ROOT_PASS"       \
  --cores       "$CT_CORES"           \
  --memory      "$CT_RAM"             \
  --swap        512                   \
  --rootfs      "${CT_STORAGE}:${CT_DISK}" \
  --net0        "name=eth0,bridge=${CT_BRIDGE},ip=${CT_IP}${CT_GW:+,gw=${CT_GW}}" \
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

# En mode DHCP, récupérer l'IP réellement attribuée
if [[ "$CT_NET_MODE" == "dhcp" ]]; then
  msg_info "Récupération de l'adresse IP DHCP"
  for i in $(seq 1 15); do
    _detected=$(pct exec "$CT_ID" -- hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -n "$_detected" && "$_detected" != "127.0.0.1" ]]; then
      CT_IP_ONLY="$_detected"
      break
    fi
    sleep 2
  done
  msg_ok "Adresse IP attribuée : ${CT_IP_ONLY}"
fi

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
