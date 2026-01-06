#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# setup.sh — Build & install MangoWC inside a Bluefin/uBlue container
#
# Goals:
# - Fully non-interactive (no prompts)
# - Work around broken "updates-archive" repo (404) seen in some Bluefin images
# - Build pinned wlroots + scenefx + mangowc into /usr
# - Optionally remove build deps at end to keep the image small
###############################################################################

# ---------- helpers ----------
log() { echo -e "\n==> $*"; }

# In many container builds you are root already; keep sudo optional.
SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

# Hard-disable any git prompts (in case something misconfigured tries to prompt)
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

# Some uBlue/Bluefin layers have a broken repo "updates-archive" that 404s.
disable_updates_archive_repo() {
  if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then
    log "Disabling broken repo: updates-archive"
    # Only change inside the [updates-archive] section
    $SUDO sed -i '/^\[updates-archive\]/,/^\[/{s/^\(enabled\s*=\s*\)1/\10/}' /etc/yum.repos.d/*.repo || true
  fi
}

# Wrapper to always avoid updates-archive (belt & suspenders).
dnf_install() { $SUDO dnf5 -y --disablerepo=updates-archive install "$@"; }
dnf_remove()  { $SUDO dnf5 -y --disablerepo=updates-archive remove  "$@"; }
dnf_upgrade() { $SUDO dnf5 -y --disablerepo=updates-archive --refresh upgrade || true; }
dnf_makecache(){ $SUDO dnf5 -y --disablerepo=updates-archive makecache || true; }

# ---------- start ----------
disable_updates_archive_repo

log "DNF cleanup/refresh"
$SUDO dnf5 -y clean all || true
dnf_upgrade
dnf_makecache

FEDORA_VERSION="$(rpm -E %fedora)"
log "Fedora release: ${FEDORA_VERSION}"

###############################################################################
# Optional extras (keep if you want them in the image)
###############################################################################
log "Install extras (kitty + qt6ct)"
dnf_install kitty qt6ct

###############################################################################
# Build dependencies (broad enough for wlroots/scenefx/mangowc)
###############################################################################
log "Install build dependencies"
dnf_install \
  gcc gcc-c++ \
  meson ninja-build \
  pkgconf-pkg-config \
  wayland-devel wayland-protocols-devel \
  libxkbcommon-devel \
  pixman-devel \
  libdrm-devel \
  mesa-libEGL-devel mesa-libgbm-devel \
  libinput-devel \
  libseat-devel \
  systemd-devel \
  libdisplay-info-devel \
  libliftoff-devel \
  git \
  xorg-x11-server-Xwayland \
  libxcb-devel xcb-util-devel xcb-util-wm-devel xcb-util-renderutil-devel xcb-util-image-devel xcb-util-keysyms-devel \
  cairo-devel pango-devel \
  glib2-devel \
  hwdata

# Some Fedora variants split/rename GLES devel; try best-effort without failing the whole build.
dnf_install mesa-libGLES-devel || true

###############################################################################
# Build & install pinned wlroots + scenefx + mangowc
###############################################################################
BUILDROOT="/tmp/mangowc-build"
log "Prepare build root: ${BUILDROOT}"
$SUDO rm -rf "${BUILDROOT}"
$SUDO mkdir -p "${BUILDROOT}"
cd "${BUILDROOT}"

# 1) wlroots (pinned)
WLROOTS_TAG="0.19.2"
log "Clone wlroots ${WLROOTS_TAG}"
git clone -b "${WLROOTS_TAG}" --depth 1 https://gitlab.freedesktop.org/wlroots/wlroots.git
cd wlroots
log "Build & install wlroots ${WLROOTS_TAG}"
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig
cd "${BUILDROOT}"

# 2) scenefx (pinned)
SCENEFX_TAG="0.4.1"
log "Clone scenefx ${SCENEFX_TAG}"
git clone -b "${SCENEFX_TAG}" --depth 1 https://github.com/wlrfx/scenefx.git
cd scenefx
log "Build & install scenefx ${SCENEFX_TAG}"
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig
cd "${BUILDROOT}"

# 3) MangoWC
log "Clone mangowc"
git clone --depth 1 https://github.com/DreamMaoMao/mangowc.git
cd mangowc
log "Build & install mangowc"
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig

###############################################################################
# Cleanup build directory
###############################################################################
log "Cleanup build directory"
cd /
$SUDO rm -rf "${BUILDROOT}"

###############################################################################
# Optional: remove build deps to reduce image size
# If you plan to compile more things later, move this block to the very end.
###############################################################################
log "Remove build dependencies (optional image slimming)"
dnf_remove \
  git \
  gcc gcc-c++ \
  meson ninja-build \
  pkgconf-pkg-config \
  wayland-devel wayland-protocols-devel \
  libxkbcommon-devel \
  pixman-devel \
  libdrm-devel \
  mesa-libEGL-devel mesa-libgbm-devel \
  libinput-devel \
  libseat-devel \
  systemd-devel \
  libxcb-devel xcb-util-devel xcb-util-wm-devel xcb-util-renderutil-devel xcb-util-image-devel xcb-util-keysyms-devel \
  cairo-devel pango-devel \
  glib2-devel \
  hwdata \
  || true

# Best-effort remove of optional GLES devel if installed
dnf_remove mesa-libGLES-devel || true

# Autoremove leftover deps (best-effort)
$SUDO dnf5 -y --disablerepo=updates-archive autoremove || true
$SUDO dnf5 -y clean all || true

log "Done. MangoWC should be installed in /usr/bin/mangowc"


# 2) Noctalia (Copr)
log "Enable COPR zhangyi6324/noctalia-shell"
dnf5 -y copr enable zhangyi6324/noctalia-shell
dnf5 -y install noctalia-shell quickshell || dnf5 -y install noctalia-shell
dnf5 -y copr disable zhangyi6324/noctalia-shell
