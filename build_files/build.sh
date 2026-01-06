#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\n==> $*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

# strip CRLF (best-effort)
$SUDO sed -i 's/\r$//' "$0" 2>/dev/null || true

# Disable broken updates-archive repo if present
if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then
  log "Disabling broken repo: updates-archive"
  $SUDO sed -i '/^\[updates-archive\]/,/^\[/{s/^\(enabled\s*=\s*\)1/\10/}' /etc/yum.repos.d/*.repo || true
fi

DNF_BASE=(dnf5 -y --disablerepo=updates-archive)

# Settings (stable defaults)
SLIM="${SLIM:-1}"                 # 1 = remove build deps at end
WLROOTS_REF="${WLROOTS_REF:-0.20.0}"
SCENEFX_REF="${SCENEFX_REF:-0.4.1}"

log "DNF cleanup/refresh"
$SUDO "${DNF_BASE[@]}" clean all || true
$SUDO "${DNF_BASE[@]}" --refresh upgrade || true
$SUDO "${DNF_BASE[@]}" makecache || true

FEDORA_VERSION="$(rpm -E %fedora)"
log "Fedora release: ${FEDORA_VERSION}"
log "wlroots ref: ${WLROOTS_REF}"
log "scenefx ref: ${SCENEFX_REF}"
log "slim: ${SLIM}"

# COPR helper
copr_install() {
  local repo="$1"; shift
  local pkgs=("$@")
  log "Enable COPR: ${repo}"
  $SUDO "${DNF_BASE[@]}" copr enable "${repo}"
  log "Install: ${pkgs[*]}"
  $SUDO "${DNF_BASE[@]}" install "${pkgs[@]}"
  log "Disable COPR: ${repo}"
  $SUDO "${DNF_BASE[@]}" copr disable "${repo}" || true
}

# 1) Niri + DMS
copr_install "avengemedia/dms" niri dms

# 2) Noctalia
log "Enable COPR: zhangyi6324/noctalia-shell"
$SUDO "${DNF_BASE[@]}" copr enable "zhangyi6324/noctalia-shell"
log "Install noctalia-shell (try with quickshell, fallback without)"
$SUDO "${DNF_BASE[@]}" install noctalia-shell quickshell || $SUDO "${DNF_BASE[@]}" install noctalia-shell
log "Disable COPR: zhangyi6324/noctalia-shell"
$SUDO "${DNF_BASE[@]}" copr disable "zhangyi6324/noctalia-shell" || true

# 3) Ghostty
copr_install "scottames/ghostty" ghostty

# 4) Extras
EXTRAS_PKGS=(kitty qt6ct)
log "Install extras: ${EXTRAS_PKGS[*]}"
$SUDO "${DNF_BASE[@]}" install "${EXTRAS_PKGS[@]}"

# Build deps
BUILD_DEPS=(
  git curl
  gcc gcc-c++
  meson ninja-build
  pkgconf-pkg-config
  wayland-devel wayland-protocols-devel
  libxkbcommon-devel
  pixman-devel
  libdrm-devel
  mesa-libEGL-devel mesa-libgbm-devel
  libinput-devel
  libseat-devel
  systemd-devel
  libdisplay-info-devel
  libliftoff-devel
  xorg-x11-server-Xwayland
  libxcb-devel xcb-util-devel xcb-util-wm-devel xcb-util-renderutil-devel xcb-util-image-devel xcb-util-keysyms-devel
  cairo-devel pango-devel
  glib2-devel
  hwdata
)

log "Install build dependencies"
$SUDO "${DNF_BASE[@]}" install "${BUILD_DEPS[@]}"
$SUDO "${DNF_BASE[@]}" install mesa-libGLES-devel || true

# Resolve latest MangoWC release tag
log "Resolving latest mangowc GitHub release tag"
MANGOWC_REF="$(
  curl -fsSL "https://api.github.com/repos/DreamMaoMao/mangowc/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n1
)"
if [[ -z "${MANGOWC_REF}" ]]; then
  echo "ERROR: Could not resolve mangowc release tag (GitHub API). Try again or pin manually." >&2
  exit 1
fi
log "Latest mangowc release: ${MANGOWC_REF}"

# Build
BUILDROOT="/tmp/mangowc-build"
log "Prepare build root: ${BUILDROOT}"
$SUDO rm -rf "${BUILDROOT}"
$SUDO mkdir -p "${BUILDROOT}"
cd "${BUILDROOT}"

# wlroots (pinned release tag)
log "Clone wlroots (${WLROOTS_REF})"
git clone https://gitlab.freedesktop.org/wlroots/wlroots.git
cd wlroots
git checkout "${WLROOTS_REF}"
meson setup build -Dprefix=/usr -Dbuildtype=release -Dexamples=false
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig
cd "${BUILDROOT}"

# scenefx (pinned release tag)
log "Clone scenefx (${SCENEFX_REF})"
git clone https://github.com/wlrfx/scenefx.git
cd scenefx
git checkout "${SCENEFX_REF}"
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig
cd "${BUILDROOT}"

# mangowc (latest release)
log "Clone mangowc (${MANGOWC_REF})"
git clone https://github.com/DreamMaoMao/mangowc.git
cd mangowc
git checkout "${MANGOWC_REF}"
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig

log "Cleanup build directory"
cd /
$SUDO rm -rf "${BUILDROOT}"

if [[ "${SLIM}" == "1" ]]; then
  log "Slim mode: removing build dependencies"
  $SUDO "${DNF_BASE[@]}" remove "${BUILD_DEPS[@]}" || true
  $SUDO "${DNF_BASE[@]}" remove mesa-libGLES-devel || true
  $SUDO "${DNF_BASE[@]}" autoremove || true
  $SUDO "${DNF_BASE[@]}" clean all || true
fi

log "Done. MangoWC installed at /usr/bin/mangowc"
