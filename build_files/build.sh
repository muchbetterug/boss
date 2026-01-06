#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# setup.sh — Install MangoWC in a Bluefin/uBlue container (buildah-friendly)
#
# Defaults:
#   MANGO_CHANNEL=release   -> build latest GitHub Release tag (stable-ish)
#   SLIM=1                  -> remove build deps at end to reduce image size
#
# Optional:
#   MANGO_CHANNEL=git       -> build mangowc master + wlroots master + scenefx
#   SLIM=0                  -> keep build deps (debugging)
###############################################################################

log() { echo -e "\n==> $*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

# Never prompt for git credentials
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

# Best-effort: strip CRLF if file edited on Windows
$SUDO sed -i 's/\r$//' "$0" 2>/dev/null || true

# Settings
MANGO_CHANNEL="${MANGO_CHANNEL:-release}"  # release | git
SLIM="${SLIM:-1}"                          # 1 | 0

# Disable broken updates-archive repo if present (some uBlue/Bluefin layers)
if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then
  log "Disabling broken repo: updates-archive"
  $SUDO sed -i '/^\[updates-archive\]/,/^\[/{s/^\(enabled\s*=\s*\)1/\10/}' /etc/yum.repos.d/*.repo || true
fi

# Always disallow updates-archive as an extra safety net
DNF_BASE=(dnf5 -y --disablerepo=updates-archive)

log "DNF cleanup/refresh"
$SUDO "${DNF_BASE[@]}" clean all || true
$SUDO "${DNF_BASE[@]}" --refresh upgrade || true
$SUDO "${DNF_BASE[@]}" makecache || true

FEDORA_VERSION="$(rpm -E %fedora)"
log "Fedora release: ${FEDORA_VERSION}"
log "Mango channel: ${MANGO_CHANNEL}"
log "Slim mode: ${SLIM}"

###############################################################################
# COPR packages (optional but requested in your original flow)
###############################################################################

# Helper to enable/install/disable COPR safely
copr_install() {
  local repo="$1"; shift
  local pkgs=("$@")
  log "Enable COPR: ${repo}"
  $SUDO "${DNF_BASE[@]}" copr enable "${repo}"
  log "Install from COPR: ${pkgs[*]}"
  $SUDO "${DNF_BASE[@]}" install "${pkgs[@]}"
  log "Disable COPR: ${repo}"
  $SUDO "${DNF_BASE[@]}" copr disable "${repo}" || true
}

# 1) Niri + DMS (Copr)
copr_install "avengemedia/dms" niri dms

# 2) Noctalia (Copr) — quickshell optional
log "Enable COPR: zhangyi6324/noctalia-shell"
$SUDO "${DNF_BASE[@]}" copr enable "zhangyi6324/noctalia-shell"
log "Install noctalia-shell (try with quickshell, fallback without)"
$SUDO "${DNF_BASE[@]}" install noctalia-shell quickshell || \
  $SUDO "${DNF_BASE[@]}" install noctalia-shell
log "Disable COPR: zhangyi6324/noctalia-shell"
$SUDO "${DNF_BASE[@]}" copr disable "zhangyi6324/noctalia-shell" || true

# 3) Ghostty (Copr)
copr_install "scottames/ghostty" ghostty

# 4) Extras
EXTRAS_PKGS=(kitty qt6ct)
log "Install extras: ${EXTRAS_PKGS[*]}"
$SUDO "${DNF_BASE[@]}" install "${EXTRAS_PKGS[@]}"

###############################################################################
# Build dependencies
###############################################################################
# Note: wlroots master often wants libdisplay-info + libliftoff around; keep them.
BUILD_DEPS=(
  git
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
  curl
)

log "Install build dependencies"
$SUDO "${DNF_BASE[@]}" install "${BUILD_DEPS[@]}"
$SUDO "${DNF_BASE[@]}" install mesa-libGLES-devel || true

###############################################################################
# Build & install wlroots + scenefx + mangowc
###############################################################################
BUILDROOT="/tmp/mangowc-build"
log "Prepare build root: ${BUILDROOT}"
$SUDO rm -rf "${BUILDROOT}"
$SUDO mkdir -p "${BUILDROOT}"
cd "${BUILDROOT}"

# Decide versions depending on channel
WLROOTS_REF="master"
SCENEFX_REF="master"
MANGOWC_REF="master"

# For the "release" channel:
# - Build latest mangowc release tag
# - Use scenefx 0.4.x release (per mangowc release notes: it stopped tracking scenefx main) :contentReference[oaicite:1]{index=1}
# - wlroots: still build from git master by default (keeps it compatible with the mangowc release even if Fedora repos lag)
#   If you prefer fully release-pinned wlroots too, you can later set WLROOTS_REF to a tag that matches.
if [[ "${MANGO_CHANNEL}" == "release" ]]; then
  log "Resolving latest mangowc GitHub release tag"
  # GitHub API (no auth). If rate-limited, you can pin manually.
  MANGOWC_REF="$(
    curl -fsSL "https://api.github.com/repos/DreamMaoMao/mangowc/releases/latest" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n1
  )"
  if [[ -z "${MANGOWC_REF}" ]]; then
    echo "ERROR: Could not resolve mangowc release tag (GitHub API). Set MANGOWC_REF manually or use MANGO_CHANNEL=git." >&2
    exit 1
  fi
  log "Latest mangowc release: ${MANGOWC_REF}"

  # ScenefX: pin to 0.4.x (released). If you want a specific one, set SCENEFX_REF=0.4.1 etc.
  SCENEFX_REF="${SCENEFX_REF:-0.4.1}"
  log "Using scenefx release tag: ${SCENEFX_REF} (recommended for stability)"
fi

###############################################################################
# 1) wlroots
###############################################################################
log "Clone wlroots (${WLROOTS_REF})"
git clone --depth 1 https://gitlab.freedesktop.org/wlroots/wlroots.git
cd wlroots
if [[ "${WLROOTS_REF}" != "master" ]]; then
  git fetch --depth 1 origin "${WLROOTS_REF}"
  git checkout "${WLROOTS_REF}"
fi

log "Build & install wlroots (${WLROOTS_REF})"
meson setup build -Dprefix=/usr -Dbuildtype=release -Dexamples=false
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig
cd "${BUILDROOT}"

###############################################################################
# 2) scenefx
###############################################################################
log "Clone scenefx (${SCENEFX_REF})"
git clone https://github.com/wlrfx/scenefx.git
cd scenefx
if [[ "${SCENEFX_REF}" != "master" ]]; then
  git fetch --depth 1 origin "refs/tags/${SCENEFX_REF}:refs/tags/${SCENEFX_REF}" || true
  git checkout "${SCENEFX_REF}"
else
  git checkout master || true
  git pull --ff-only || true
fi

log "Build & install scenefx (${SCENEFX_REF})"
meson setup build -Dprefix=/usr -Dbuildtype=release
ninja -C build
$SUDO ninja -C build install
$SUDO ldconfig
cd "${BUILDROOT}"

###############################################################################
# 3) mangowc
###############################################################################
log "Clone mangowc (${MANGOWC_REF})"
git clone https://github.com/DreamMaoMao/mangowc.git
cd mangowc
if [[ "${MANGOWC_REF}" != "master" ]]; then
  git fetch --depth 1 origin "refs/tags/${MANGOWC_REF}:refs/tags/${MANGOWC_REF}" || true
  git checkout "${MANGOWC_REF}"
else
  git checkout master || true
  git pull --ff-only || true
fi

log "Build & install mangowc (${MANGOWC_REF})"
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

log "Done. MangoWC should be installed at /usr/bin/mangowc"
