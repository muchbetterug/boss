#!/usr/bin/env bash
set -euo pipefail

sudo dnf5 -y clean all
sudo dnf5 -y --refresh upgrade || true

# falls vorhanden: kaputtes repo abschalten
sudo dnf5 config-manager setopt updates-archive.enabled=0 || true

sudo dnf5 -y makecache

# Bluefin build script helper
log() { echo -e "\n==> $*"; }

FEDORA_VERSION="$(rpm -E %fedora)"

log "Fedora: ${FEDORA_VERSION}"

# 1) Niri + DMS (Copr)
log "Enable COPR avengemedia/dms"
dnf5 -y copr enable avengemedia/dms
dnf5 -y install niri dms
dnf5 -y copr disable avengemedia/dms

# 2) Noctalia (Copr)
log "Enable COPR zhangyi6324/noctalia-shell"
dnf5 -y copr enable zhangyi6324/noctalia-shell
dnf5 -y install noctalia-shell quickshell || dnf5 -y install noctalia-shell
dnf5 -y copr disable zhangyi6324/noctalia-shell

# 3) Ghostty (Copr)
log "Enable COPR scottames/ghostty"
dnf5 -y copr enable scottames/ghostty
dnf5 -y install ghostty
dnf5 -y copr disable scottames/ghostty

# 4) Extras
dnf5 -y install kitty qt6ct

# 0) Build deps installieren
# (Liste ist bewusst etwas "breiter", damit Meson nicht mitten im Build wegen fehlender -devel Pakete abbricht.)
dnf5 -y install \
  git \
  gcc gcc-c++ \
  meson ninja-build \
  pkgconf-pkg-config \
  wayland-devel wayland-protocols-devel \
  libxkbcommon-devel \
  pixman-devel \
  libdrm-devel \
  mesa-libEGL-devel mesa-libGLES-devel mesa-libgbm-devel \
  libinput-devel \
  libseat-devel \
  systemd-devel \
  xorg-x11-server-Xwayland \
  libxcb-devel xcb-util-devel xcb-util-wm-devel xcb-util-renderutil-devel xcb-util-image-devel xcb-util-keysyms-devel \
  cairo-devel pango-devel \
  glib2-devel \
  hwdata

# 1) Build wlroots (pinned)
# Doku: git clone -b 0.19.2 ... meson build -Dprefix=/usr ... ninja install :contentReference[oaicite:3]{index=3}
rm -rf /tmp/mangowc-build
mkdir -p /tmp/mangowc-build
cd /tmp/mangowc-build

git clone -b 0.19.2 --depth 1 https://gitlab.freedesktop.org/wlroots/wlroots.git
cd wlroots
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build install
cd ..

# 2) Build scenefx (pinned)
# Doku: git clone -b 0.4.1 ... meson build -Dprefix=/usr ... ninja install :contentReference[oaicite:4]{index=4}
git clone -b 0.4.1 --depth 1 https://github.com/wlrfx/scenefx.git
cd scenefx
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build install
cd ..

# 3) Build MangoWC
# Doku: "Finally, compile the compositor itself." (Meson/Ninja analog) :contentReference[oaicite:5]{index=5}
git clone --depth 1 https://github.com/DreamMaoMao/mangowc.git
cd mangowc
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build install

# 4) Cleanup: Build-Verzeichnis entfernen
cd /
rm -rf /tmp/mangowc-build

# Optional: Build deps entfernen, um Image klein zu halten
# (Wenn du später im Build noch mehr kompilierst, dann erst ganz am Ende entfernen.)
dnf5 -y remove \
  git \
  gcc gcc-c++ \
  meson ninja-build \
  pkgconf-pkg-config \
  wayland-devel wayland-protocols-devel \
  libxkbcommon-devel \
  pixman-devel \
  libdrm-devel \
  mesa-libEGL-devel mesa-libGLES-devel mesa-libgbm-devel \
  libinput-devel \
  libseatd-devel \
  systemd-devel \
  libxcb-devel xcb-util-devel xcb-util-wm-devel xcb-util-renderutil-devel xcb-util-image-devel xcb-util-keysyms-devel \
  cairo-devel pango-devel \
  glib2-devel \
  hwdata || true

dnf5 -y clean all
