# 🦊 Firefox & Thunderbird: snap → deb

> Ubuntu and Kubuntu ship Firefox and Thunderbird as **snap** packages by default. This script removes both snaps and reinstalls them via **APT** using the official [Mozilla PPA](https://launchpad.net/~mozillateam/+archive/ubuntu/ppa), giving you native `.deb` packages with proper system integration.

---

## ✨ What it does

1. Unmounts the Firefox snap `hunspell` mount unit (avoids errors during removal)
2. Removes `firefox` and `thunderbird` snap packages with `--purge`
3. Removes any leftover APT stubs
4. Creates **APT pin files** to permanently block Ubuntu from reinstalling the snap versions
5. Adds the Mozilla PPA (`ppa:mozillateam/ppa`)
6. Installs Firefox and Thunderbird from the Mozilla PPA
7. Configures `unattended-upgrades` so they stay up-to-date automatically
8. Runs a final check to confirm the installed versions are **not** snap symlinks

---

## 📋 Requirements

- Ubuntu or Kubuntu (22.04, 24.04, or newer)
- `curl` or `wget` to run the one-liner
- Internet connection
- `sudo` access

> `software-properties-common` is installed automatically if missing.

---

## 🚀 Installation

### One-liner

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Alexys829/firefox-thunderbird-snap-to-deb/main/remove_snap_install_deb.sh)
```

### Manual

```bash
git clone https://github.com/Alexys829/firefox-thunderbird-snap-to-deb.git
cd firefox-thunderbird-snap-to-deb
chmod +x remove_snap_install_deb.sh
./remove_snap_install_deb.sh
```

> The script auto-elevates with `sudo` if not run as root.

---

## ⚙️ How it works

```
Run script
    │
    ├─ Unmount Firefox snap hunspell unit
    ├─ snap remove --purge firefox thunderbird
    ├─ apt-get remove --purge firefox thunderbird (stubs)
    ├─ Create APT pin files (block Ubuntu snap reinstall)
    ├─ add-apt-repository ppa:mozillateam/ppa
    ├─ apt-get install firefox thunderbird (from Mozilla PPA)
    ├─ Configure unattended-upgrades for Mozilla PPA
    └─ Verify: check versions + confirm not snap symlinks
```

---

## 🛡️ APT Pin files created

| File | Purpose |
|---|---|
| `/etc/apt/preferences.d/firefox-no-snap` | Blocks Ubuntu's snap-backed Firefox |
| `/etc/apt/preferences.d/thunderbird-no-snap` | Blocks Ubuntu's snap-backed Thunderbird |

These pins set `Pin-Priority: -1` for packages from Ubuntu origins, so `apt upgrade` will never silently swap back to snap.

---

## 🗑️ Undo / Uninstall

To revert to snap versions:

```bash
sudo rm /etc/apt/preferences.d/firefox-no-snap
sudo rm /etc/apt/preferences.d/thunderbird-no-snap
sudo rm /etc/apt/apt.conf.d/51unattended-upgrades-mozilla
sudo apt-get remove --purge firefox thunderbird
sudo snap install firefox
sudo snap install thunderbird
```

---

## 📄 License

MIT — do whatever you want with it.
