#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# setup.sh — Install MangoWC (stable-current) in a Bluefin/uBlue container
#
# Design goals:
# - MangoWC: always latest GitHub RELEASE (current, but stable-ish)
# - wlroots: pinned to a real RELEASE tag (default: 0.19.2) to avoid wlroots-master
#            deps like libdrm>=2.4.129 which Fedora 42/Bluefin may not have yet
# - scenefx: pinned to released 0.4.1 (stable), not master
# - Works in buildah/CI: no fragile "\" line continuations (uses arrays)
# - Avoid broken "updates-archive" repo (404) seen in some uBlue layers
# - Non-interactive git
# - Optional: remove build deps at end (SLIM=1 default)
#
# Tunables:
#   WLROOTS_REF=0.19.2        # wlroots release tag (try 0.19.2 first)
#   SCENEFX_REF=0.4.1         # scenefx release tag
#   SLIM=1                    # 1 remove build deps at end, 0 keep them
###############################################################################

log() { echo -e "\n==> $*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

# Never prompt for git credentials
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

# Best-effort: strip CRLF if edited on Windows
$SUDO sed -i 's/\r$//' "$0" 2>/dev/null || true

# Tunables
WLROOTS_REF="${WLROOTS_REF:-0.19.2}"
SCENEFX_REF="${SCENEFX_REF:-0.4.1}"
SLIM="${SLIM:-1}"

# Disable broken updates-archive repo if present
if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then
  log "Disabling broken repo: updates-archive"
  $SUDO sed -i '/^\[updates-archive\]/,/^\[/{s/^\(enabled\s*=\s*\)1/\10/}' /etc/yum.repos.d/*.repo || true
fi

# Always disallow updates-archive as extra safety net
DNF_BASE=(dnf5 -y --disablerepo=updates-archive)

log "DNF cleanup/refresh"
$SUDO "${DNF_BASE[@]}" clean all || true
$SUDO "${DNF_BASE[@]}" --refresh upgrade || true
$SUDO "${DNF_BASE[@]}" makecache || true

FEDORA_VERSION="$(rpm -E %fedora)"
log "Fedora release: ${FEDORA_VERSION}"
log "wlroots tag: ${WLROOTS_REF}"
log "scenefx tag: ${SCENEFX_REF}"
log "slim: ${SLIM}"

###############################################################################
# COPR helpers & installs
###############################################################################
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

# 2) Noctalia (try quickshell, fallback without)
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

###############################################################################
# Build dependencies
###############################################################################
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

  # Often needed by wlroots builds on Fedora
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

###############################################################################
# Resolve latest MangoWC release tag
###############################################################################
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

###############################################################################
# Build & install wlroots + scenefx + mangowc
###############################################################################
BUILDROOT="/tmp/mangowc-build"
log "Prepare build root: ${BUILDROOT}"
$SUDO rm -rf "${BUILDROOT}"
$SUDO mkdir -p "${BUILDROOT}"
cd "${BUILDROOT}"

# --- wlroots ---
log "Clone wlroots"
git clone https://gitlab.freedesktop.org/wlroots/wlroots.git
cd wlroots
git fetch --tags --force

# allow both "0.19.2" and "v0.19.2"
if git rev-parse -q --verify "refs/tags/${WLROOTS_REF}" >/dev/null; then
  log "Checkout wlroots tag: ${WLROOTS_REF}"
  git checkout "refs/tags/${WLROOTS_REF}"
elif git rev-parse -q --verify "refs/tags/v${WLROOTS_REF}" >/dev/null; then
  log "Checkout wlroots tag: v${WLROOTS_REF}"
  git checkout "refs/tags/v${WLROOTS_REF}"
else
  echo "ERROR: wlroots tag '${WLROOTS_REF}' not found." >&2
  echo "Available tags (last 30):" >&2
  git tag --list | tail -n 30 >&2
  exit 1
fi

log "Build & install wlroots"
meson setup build -Dprefix=/usr -Dbuildtype=release -Dexamples=false
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig
cd "${BUILDROOT}"

# --- scenefx ---
log "Clone scenefx"
git clone https://github.com/wlrfx/scenefx.git
cd scenefx
git fetch --tags --force

if git rev-parse -q --verify "refs/tags/${SCENEFX_REF}" >/dev/null; then
  log "Checkout scenefx tag: ${SCENEFX_REF}"
  git checkout "refs/tags/${SCENEFX_REF}"
elif git rev-parse -q --verify "refs/tags/v${SCENEFX_REF}" >/dev/null; then
  log "Checkout scenefx tag: v${SCENEFX_REF}"
  git checkout "refs/tags/v${SCENEFX_REF}"
else
  echo "ERROR: scenefx tag '${SCENEFX_REF}' not found." >&2
  echo "Available tags (last 30):" >&2
  git tag --list | tail -n 30 >&2
  exit 1
fi

log "Build & install scenefx"
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig
cd "${BUILDROOT}"

# --- mangowc (latest release) ---
log "Clone mangowc"
git clone https://github.com/DreamMaoMao/mangowc.git
cd mangowc
git fetch --tags --force

if git rev-parse -q --verify "refs/tags/${MANGOWC_REF}" >/dev/null; then
  log "Checkout mangowc tag: ${MANGOWC_REF}"
  git checkout "refs/tags/${MANGOWC_REF}"
elif git rev-parse -q --verify "refs/tags/v${MANGOWC_REF}" >/dev/null; then
  log "Checkout mangowc tag: v${MANGOWC_REF}"
  git checkout "refs/tags/v${MANGOWC_REF}"
else
  echo "ERROR: mangowc tag '${MANGOWC_REF}' not found in repo tags." >&2
  echo "Available tags (last 30):" >&2
  git tag --list | tail -n 30 >&2
  exit 1
fi

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
# Optional slimming
###############################################################################
if [[ "${SLIM}" == "1" ]]; then
  log "Slim mode: removing build dependencies"
  $SUDO "${DNF_BASE[@]}" remove "${BUILD_DEPS[@]}" || true
  $SUDO "${DNF_BASE[@]}" remove mesa-libGLES-devel || true
  $SUDO "${DNF_BASE[@]}" autoremove || true
  $SUDO "${DNF_BASE[@]}" clean all || true
else
  log "Slim mode disabled: keeping build deps installed"
fi

log "Done. MangoWC installed at /usr/bin/mangowc"
