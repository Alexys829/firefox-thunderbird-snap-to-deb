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
    if [[ -f "$0" && -r "$0" ]]; then
        exec sudo bash "$0" "$@"
    else
        # Avviato via pipe o process substitution (es. bash <(curl ...)):
        # $0 punta a un FD non accessibile da sudo. Copiamo in un file temporaneo.
        tmp=$(mktemp /tmp/snap2deb.XXXXXX.sh)
        cat "$0" > "$tmp"
        chmod +x "$tmp"
        exec sudo bash "$tmp" "$@"
    fi
fi

# ── Verifica distro supportata ──────────────────────────
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *ubuntu* ]]; then
        die "Distro non supportata (${PRETTY_NAME:-sconosciuta}). Richiesto Ubuntu o derivate."
    fi
else
    die "Impossibile leggere /etc/os-release."
fi

# Rileva codename distro (serve per PPA e unattended-upgrades)
distro_codename=$(lsb_release -cs 2>/dev/null || echo "${VERSION_CODENAME:-}")
[[ -n "$distro_codename" ]] || die "Impossibile rilevare il codename della distro."

# ── Verifica dipendenza software-properties-common ──────────
if ! command -v add-apt-repository &>/dev/null; then
    info "Installazione software-properties-common (necessario per add-apt-repository)..."
    apt-get update -q
    apt-get install -y software-properties-common
    success "software-properties-common installato."
fi

# ── 1. Smonta mount unit hunspell (Firefox snap) ────────────
info "Pulizia mount unit hunspell di Firefox snap..."
MOUNT_UNIT=$(systemd-escape -p --suffix=mount /var/snap/firefox/common/host-hunspell)
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
apt-get remove --purge -y firefox thunderbird || true
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
if compgen -G "/etc/apt/sources.list.d/mozillateam-ubuntu-ppa-*.list" > /dev/null; then
    info "PPA Mozilla già presente."
else
    add-apt-repository -y ppa:mozillateam/ppa
    success "PPA Mozilla aggiunto."
fi

# ── 5. Aggiornamento indice pacchetti ───────────────────────
info "Aggiornamento lista pacchetti..."
apt-get update -q || die "Aggiornamento pacchetti fallito."

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
