#!/bin/bash
set -ouex pipefail

RELEASE="$(rpm -E %fedora)"

log() {
  echo "=== $* ==="
}

#######################################################################
# Setup Repositories
#######################################################################

# COSMIC liegt komplett in den offiziellen Fedora-Repos -> kein Copr nötig.

# fedoraproject-updates-archive liefert in manchen Basis-Images 404 -> hart abschalten
log "Disable Fedora updates-archive repos (404 in some base images)..."
dnf5 -y config-manager setopt '*updates-archive*.enabled=0' || true
dnf5 -y config-manager setopt '*-updates-archive.enabled=0' || true

# Refresh metadata/caches
log "Refresh dnf metadata (Fedora ${RELEASE})..."
dnf5 clean all || true
rm -rf /var/cache/dnf /var/cache/libdnf5 || true
dnf5 makecache --refresh || true

#######################################################################
## Install Packages
#######################################################################

# cosmic-session zieht den kompletten Desktop als *harte* Abhängigkeit nach:
# cosmic-comp, -panel, -applets, -launcher, -settings(-daemon), -files, -term,
# -workspaces, -notifications, -osd, -bg, -idle, -randr, -screenshot,
# -app-library, -icons, -initial-setup, cosmic-greeter, xdg-desktop-portal-cosmic
# sowie cosmic-config-fedora (liefert "system-cosmic-config").
COSMIC_PKGS=(
  cosmic-session
  cosmic-edit
  cosmic-icon-theme
  cosmic-store # verwaltet Flatpaks (Flathub), nicht das bootc-Image selbst
  cosmic-wallpapers # nur "Recommends", wird mit install_weak_deps=False sonst weggelassen
  xdg-desktop-portal-cosmic
)

# Weitere COSMIC-Apps nach Geschmack: cosmic-player, cosmic-monitor

FONTS=(
  # von cosmic-session hart verlangt, hier nur zur Dokumentation explizit gelistet
  google-noto-sans-mono-fonts
  open-sans-fonts

  fira-code-fonts
  fontawesome-fonts-all
  google-noto-emoji-fonts
)

# Special GUI apps that need to be installed at the system level.
ADDITIONAL_SYSTEM_APPS=(
  kitty
  kitty-terminfo
)

log "Installing packages using dnf5..."
dnf5 install -y \
  --setopt=install_weak_deps=False \
  --setopt=ip_resolve=4 \
  --setopt=retries=20 \
  --setopt=timeout=60 \
  --disablerepo='*updates-archive*' \
  --skip-unavailable \
  "${COSMIC_PKGS[@]}" \
  "${FONTS[@]}" \
  "${ADDITIONAL_SYSTEM_APPS[@]}"

#######################################################################
### Display-Manager / Sessions
#######################################################################

# Bluefin bleibt bei GDM. Wichtig: cosmic-greeter.service hat
# "Alias=display-manager.service" und wird von Fedoras
# /usr/lib/systemd/system-preset/85-display-manager.preset automatisch aktiviert
# (rhbz#2305602) -> würde mit GDM um den display-manager-Symlink streiten.
log "Keep GDM as display manager, disable cosmic-greeter..."
systemctl disable cosmic-greeter.service || true
systemctl --force enable gdm.service

# cosmic-greeter-daemon macht die PAM-Authentifizierung für den COSMIC-Lockscreen
# und steht *nicht* im Preset -> explizit aktivieren, sonst lässt sich eine gesperrte
# COSMIC-Session nicht mehr entsperren.
log "Enable cosmic-greeter-daemon (needed by the COSMIC lock screen)..."
systemctl enable cosmic-greeter-daemon.service

# Sanity-Check: ohne diese Datei taucht COSMIC in der GDM-Sessionauswahl nicht auf.
log "Verify COSMIC wayland session is present..."
test -f /usr/share/wayland-sessions/cosmic.desktop

#######################################################################
### Cleanup
#######################################################################

# bootc container lint will /run leer und /var ohne Datei-Leichen sehen.
log "Clean up build leftovers..."
dnf5 clean all || true
rm -rf /var/lib/dnf/repos /run/dnf /run/selinux-policy || true

#######################################################################
### NVIDIA
#######################################################################

# nvidia-drm.modeset=1 setzt das bluefin-nvidia-Image schon selbst, cosmic-comp
# läuft damit auf dem proprietären Treiber (explicit sync ab Treiber 555).
# Falls es auf Multi-Monitor flackert/tearing gibt, hilft meist Direct Scanout aus:
#
# install -Dm0644 /dev/stdin /usr/lib/environment.d/90-cosmic-nvidia.conf <<'EOF'
# COSMIC_DISABLE_DIRECT_SCANOUT=1
# EOF
