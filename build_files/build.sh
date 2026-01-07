#!/bin/bash
set -ouex pipefail

RELEASE="$(rpm -E %fedora)"

log() {
  echo "=== $* ==="
}

USE_SDDM=FALSE

#######################################################################
# Setup Repositories
#######################################################################

log "Enable Copr repos..."
COPR_REPOS=(
  erikreider/SwayNotificationCenter # swaync
  errornointernet/packages
  heus-sueh/packages                # matugen/swww (hyprpanel)
  leloubil/wl-clip-persist
  solopasha/hyprland
  tofik/sway
  ulysj/xwayland-satellite
  yalter/niri
)

for repo in "${COPR_REPOS[@]}"; do
  if ! dnf5 -y copr enable "$repo" 2>&1; then
    log "Warning: Failed to enable COPR repo $repo (may not support Fedora $RELEASE)"
  fi
done

#######################################################################
# Packages
#######################################################################

FONTS=(
  fira-code-fonts
  fontawesome-fonts-all
  google-noto-emoji-fonts
)

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

# Qt-dependent extras only on non-bazzite
if ! grep -qi "bazzite" /usr/lib/os-release 2>/dev/null; then
  HYPR_PKGS+=(
    hyprsysteminfo
    hyprpolkitagent
    hyprland-qt-support
  )
fi

NIRI_PKGS=(
  niri
  swaylock
)

SDDM_PACKAGES=()
if [[ $USE_SDDM == TRUE ]]; then
  SDDM_PACKAGES=(
    sddm
    sddm-breeze
    sddm-kcm
    qt6-qt5compat
  )
fi

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
  gcc gcc-c++
  clang llvm
  cmake meson
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

#######################################################################
# Install Packages (single transaction)
#######################################################################

log "Installing packages using dnf5..."
dnf5 install --skip-unavailable --setopt=install_weak_deps=False -y \
  "${FONTS[@]}" \
  "${HYPR_DEPS[@]}" \
  "${HYPR_PKGS[@]}" \
  "${NIRI_PKGS[@]}" \
  "${SDDM_PACKAGES[@]}" \
  "${ADDITIONAL_SYSTEM_APPS[@]}" \
  "${BUILD_DEPS[@]}"

#######################################################################
# Disable COPR repos to reduce clutter
#######################################################################

log "Disable Copr repos to get rid of clutter..."
for repo in "${COPR_REPOS[@]}"; do
  dnf5 -y copr disable "$repo"
done

#######################################################################
# Noctalia Shell (+ quickshell) via COPR
#######################################################################
log "Enable COPR: zhangyi6324/noctalia-shell"
dnf5 -y copr enable zhangyi6324/noctalia-shell

log "Install Noctalia Shell + quickshell"
dnf5 --setopt=install_weak_deps=False -y install noctalia-shell quickshell
dnf5 -y copr disable zhangyi6324/noctalia-shell

#######################################################################
# Enable Services (placeholder)
#######################################################################

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
