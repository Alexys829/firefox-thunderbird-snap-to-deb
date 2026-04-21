#!/usr/bin/env bash
# ============================================================
# remove_snap_install_deb.sh
# Rimuove Firefox e Thunderbird snap e li reinstalla via APT
# (PPA Mozilla) su Ubuntu/Kubuntu
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Elevazione automatica ──────────────────────────────
if [[ $EUID -ne 0 ]]; then
    warn "Script non avviato come root. Tentativo di elevazione con sudo..."
    exec sudo bash "$0" "$@"
fi

# ── Verifica dipendenza software-properties-common ──────────
if ! command -v add-apt-repository &>/dev/null; then
    info "Installazione software-properties-common (necessario per add-apt-repository)..."
    apt-get install -y software-properties-common
    success "software-properties-common installato."
fi

# ── 1. Smonta mount unit hunspell (Firefox snap) ────────────
info "Pulizia mount unit hunspell di Firefox snap..."
MOUNT_UNIT="var-snap-firefox-common-host\\x2dhunspell.mount"
if systemctl is-active --quiet "$MOUNT_UNIT" 2>/dev/null; then
    systemctl stop "$MOUNT_UNIT" || true
    systemctl disable "$MOUNT_UNIT" || true
    umount /var/snap/firefox/common/host-hunspell 2>/dev/null || true
    success "Mount unit smontata."
else
    info "Mount unit non attiva, passo oltre."
fi

# ── 2. Rimozione snap ───────────────────────────────────
for app in firefox thunderbird; do
    if snap list "$app" &>/dev/null; then
        info "Rimozione snap: $app"
        snap remove --purge "$app" && success "$app snap rimosso."
    else
        info "Snap $app non installato, passo oltre."
    fi
done

# Rimuovi eventuali stub APT rimasti
info "Rimozione stub APT Firefox/Thunderbird..."
apt-get remove --purge -y firefox thunderbird 2>/dev/null || true
apt-get autoremove -y
success "Stub APT rimossi."

# ── 3. Pin APT: blocca reinstallazione snap da Ubuntu ───────
info "Creazione pin APT per bloccare versioni snap Ubuntu..."

cat > /etc/apt/preferences.d/firefox-no-snap << 'PINEOF'
Package: firefox*
Pin: release o=Ubuntu*
Pin-Priority: -1
PINEOF

cat > /etc/apt/preferences.d/thunderbird-no-snap << 'PINEOF'
Package: thunderbird*
Pin: release o=Ubuntu*
Pin-Priority: -1
PINEOF

success "Pin APT creati."

# ── 4. Aggiunta PPA Mozilla ────────────────────────────
info "Aggiunta PPA Mozilla (ppa:mozillateam/ppa)..."
PPA_FILE="/etc/apt/sources.list.d/mozillateam-ubuntu-ppa-*.list"
if ! ls $PPA_FILE &>/dev/null; then
    add-apt-repository -y ppa:mozillateam/ppa
    success "PPA Mozilla aggiunto."
else
    info "PPA Mozilla già presente."
fi

# ── 5. Aggiornamento indice pacchetti ───────────────────────
info "Aggiornamento lista pacchetti..."
apt-get update -q || die "Aggiornamento pacchetti fallito."

# Rileva codename distro per configurazione aggiornamenti
distro_codename=$(lsb_release -cs 2>/dev/null) || distro_codename=$(. /etc/os-release && echo "$VERSION_CODENAME")

# ── 6. Installazione Firefox e Thunderbird via APT ──────────
info "Installazione Firefox dal PPA Mozilla..."
apt-get install -y -t 'o=LP-PPA-mozillateam' firefox
success "Firefox installato."

info "Installazione Thunderbird dal PPA Mozilla..."
apt-get install -y -t 'o=LP-PPA-mozillateam' thunderbird
success "Thunderbird installato."

# ── 7. Aggiornamenti automatici abilitati ───────────────────
info "Configurazione aggiornamenti automatici per PPA Mozilla..."
cat > /etc/apt/apt.conf.d/51unattended-upgrades-mozilla << AUTOEOF
Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:${distro_codename}";
AUTOEOF
success "Aggiornamenti automatici configurati."

# ── 8. Verifica finale ──────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${GREEN} Verifica versioni installate${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"

for app in firefox thunderbird; do
    APP_PATH=$(command -v "$app") || true
    if [[ -n "$APP_PATH" ]]; then
        VER=$("$app" --version 2>/dev/null || echo "N/D")
        success "$app → $VER"
        if [[ -L "$APP_PATH" ]] && readlink "$APP_PATH" | grep -q snap; then
            warn "$app punta ancora a snap! Riavvia il sistema e riprova."
        fi
        ORIGIN=$(dpkg-query -W -f='${binary:Package}\n' "$app" 2>/dev/null | head -1)
        if [[ -n "$ORIGIN" ]]; then
            info "Origine pacchetto: $ORIGIN"
        fi
    else
        warn "$app non trovato nel PATH."
    fi
done

echo ""
success "Tutto completato! Firefox e Thunderbird sono ora gestiti via APT (PPA Mozilla)."
