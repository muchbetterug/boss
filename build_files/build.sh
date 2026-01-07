#!/bin/bash
set -ouex pipefail

RELEASE="$(rpm -E %fedora)"

log() {
  echo "=== $* ==="
}

# if true, sddm will be installed as the display manager.
# NOTE: NOT FULLY IMPLEMENTED AND UNTESTED, DO NOT USE YET
USE_SDDM=FALSE

#######################################################################
# Setup Repositories
#######################################################################

log "Enable Copr repos..."
COPR_REPOS=(
  erikreider/SwayNotificationCenter # for swaync
  errornointernet/packages
  heus-sueh/packages                # for matugen/swww, needed by hyprpanel
  leloubil/wl-clip-persist
  solopasha/hyprland
  tofik/sway
  ulysj/xwayland-satellite
  yalter/niri
)

for repo in "${COPR_REPOS[@]}"; do
  # Try to enable the repo, but don't fail the build if it doesn't support this Fedora version
  if ! dnf5 -y copr enable "$repo" 2>&1; then
    log "Warning: Failed to enable COPR repo $repo (may not support Fedora $RELEASE)"
  fi
done

# Your error is a 404 from fedoraproject-updates-archive.* -> disable it hard
log "Disable Fedora updates-archive repos (404 in some base images)..."
dnf5 -y config-manager setopt '*updates-archive*.enabled=0' || true
dnf5 -y config-manager setopt '*-updates-archive.enabled=0' || true

# Refresh metadata/caches
log "Refresh dnf metadata..."
dnf5 clean all || true
rm -rf /var/cache/dnf /var/cache/libdnf5 || true
dnf5 makecache --refresh || true

#######################################################################
## Install Packages
#######################################################################

FONTS=(
  fira-code-fonts
  fontawesome-fonts-all
  google-noto-emoji-fonts
)

# Hyprland runtime ecosystem deps (apps/tools)
HYPR_DEPS=(
  aquamarine
  aylurs-gtk-shell2
  blueman
  bluez
  bluez-tools
  brightnessctl
  btop
  cava
  cliphist
  eog
  fuzzel
  gnome-bluetooth
  grim
  grimblast
  gvfs
  hyprpanel
  inxi
  kvantum
  libgtop2
  mako
  matugen
  mpv
  network-manager-applet
  nodejs
  nwg-look
  pamixer
  pavucontrol
  playerctl
  python3-pyquery
  qalculate-gtk
  qt5ct
  qt6ct
  rofi
  slurp
  swappy
  swaync
  swww
  tumbler
  upower
  wallust
  waybar
  wget2
  wireplumber
  wl-clipboard
  wl-clip-persist
  wlogout
  wlr-randr
  xarchiver
  xdg-desktop-portal-gtk
  xwayland-satellite
  yad
)

# Hyprland ecosystem packages
HYPR_PKGS=(
  hyprland
  hyprcursor
  hyprpaper
  hyprpicker
  hypridle
  hyprlock
  hyprshot
  hyprsunset
  hyprutils
  xdg-desktop-portal-hyprland
)

# Detect if we're on Bazzite (has KDE/Qt 6.10) or Bluefin (has GNOME/Qt 6.9)
# These Qt-dependent packages only work on Bluefin currently due to Qt version mismatch
if ! grep -qi "bazzite" /usr/lib/os-release 2>/dev/null; then
  HYPR_PKGS+=(
    hyprsysteminfo
    hyprpolkitagent
    hyprland-qt-support
  )
fi

# Niri and its dependencies from its default config.
NIRI_PKGS=(
  niri
  swaylock
)

# SDDM not set up properly yet, so this is just a placeholder.
# For now you'll have to invoke Hyprland from the command line.
SDDM_PACKAGES=()
if [[ $USE_SDDM == TRUE ]]; then
  SDDM_PACKAGES=(
    sddm
    sddm-breeze
    sddm-kcm
    qt6-qt5compat
  )
fi

# Special GUI apps that need to be installed at the system level.
ADDITIONAL_SYSTEM_APPS=(
  alacritty
  kitty
  kitty-terminfo
  thunar
  thunar-volman
  thunar-archive-plugin
)

# Build deps for Hyprland/Hyprpm compilation (incl. NVIDIA)
BUILD_DEPS=(
  gcc
  gcc-c++
  clang
  llvm
  cmake
  meson
  pkg-config
  git
  cpio
  ninja
  python3

  wayland-devel
  wayland-protocols-devel

  libXcursor-devel
  libXrandr-devel
  libXinerama-devel
  libX11-devel
  libxcb-devel
  libXi-devel

  mesa-libGL-devel
  mesa-libEGL-devel
  mesa-libgbm-devel
  libdrm-devel

  cairo-devel
  pango-devel
  pixman-devel
  libjpeg-turbo-devel
  libpng-devel

  pipewire-jack-audio-connection-kit-devel
  libseat-devel
  dbus-devel
  systemd-devel
  libuuid-devel

  nvidia-driver
  nvidia-driver-devel
  egl-wayland

  libinput-devel
  xcb-util-wm-devel
  xcb-util-renderutil-devel
  xcb-util-devel
)

log "Installing packages using dnf5..."
dnf5 install -y \
  --setopt=install_weak_deps=False \
  --setopt=ip_resolve=4 \
  --setopt=retries=20 \
  --setopt=timeout=60 \
  --disablerepo='*updates-archive*' \
  --skip-unavailable \
  "${FONTS[@]}" \
  "${HYPR_DEPS[@]}" \
  "${HYPR_PKGS[@]}" \
  "${NIRI_PKGS[@]}" \
  "${SDDM_PACKAGES[@]}" \
  "${ADDITIONAL_SYSTEM_APPS[@]}" \
  "${BUILD_DEPS[@]}"

#######################################################################
### Disable repositories so they aren't cluttering up the final image
#######################################################################

log "Disable Copr repos to get rid of clutter..."
for repo in "${COPR_REPOS[@]}"; do
  dnf5 -y copr disable "$repo" || true
done

#######################################################################
# Noctalia Shell (+ quickshell) via COPR
#######################################################################

log "Enable COPR: zhangyi6324/noctalia-shell"
dnf5 -y copr enable zhangyi6324/noctalia-shell || true

log "Install Noctalia Shell + quickshell"
dnf5 install -y --setopt=install_weak_deps=False \
  --setopt=ip_resolve=4 \
  --setopt=retries=20 \
  --setopt=timeout=60 \
  --disablerepo='*updates-archive*' \
  --skip-unavailable \
  noctalia-shell quickshell

dnf5 -y copr disable zhangyi6324/noctalia-shell || true

#######################################################################
### Enable Services (placeholder)
#######################################################################

# TODO: these need to be run at first boot, not during image build

if [[ $USE_SDDM == TRUE ]]; then
  log "Installing sddm...."
  for login_manager in lightdm gdm lxdm lxdm-gtk3; do
    if sudo dnf list installed "$login_manager" &>>/dev/null; then
      sudo systemctl disable "$login_manager" 2>&1 | tee -a "$LOG"
    fi
  done
  systemctl set-default graphical.target
  systemctl enable sddm.service
fi
