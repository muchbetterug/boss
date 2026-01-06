#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# setup.sh — "so wenig Gefrickel wie möglich" MangoWC in Bluefin/uBlue
#
# Strategie (stabil + reproduzierbar):
#  - wlroots bleibt auf einem stabilen Release: 0.19.2
#  - scenefx bleibt auf einem stabilen Release: 0.4.1
#  - MangoWC: wir nehmen NICHT blind "latest", sondern probieren automatisch die
#    letzten Releases (neu -> alt), bis eins mit wlroots-0.19 tatsächlich baut.
#
# Ergebnis: am Ende ist MangoWC installiert, ohne wlroots-master/libdrm-wrap-Werror-Drama.
#
# Optional:
#  - EXTRAS=1 installiert kitty+qt6ct (default: 0)
#  - SLIM=1 entfernt Build-Deps am Ende (default: 1)
###############################################################################

log() { echo -e "\n==> $*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

# Git nicht-interaktiv (falls irgendwas komisch konfiguriert ist)
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

# Settings
EXTRAS="${EXTRAS:-0}"
SLIM="${SLIM:-1}"

WLROOTS_TAG="0.19.2"
SCENEFX_TAG="0.4.1"
MANGO_RELEASE_TRIES="${MANGO_RELEASE_TRIES:-20}"  # wie viele GitHub Releases rückwärts testen

BUILDROOT="/tmp/mangowc-build"
DNF_BASE=(dnf5 -y --disablerepo=updates-archive)

###############################################################################
# Repo-Fix: kaputtes updates-archive deaktivieren (Bluefin Images manchmal 404)
###############################################################################
if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then
  log "Disabling broken repo: updates-archive"
  $SUDO sed -i '/^\[updates-archive\]/,/^\[/{s/^\(enabled\s*=\s*\)1/\10/}' /etc/yum.repos.d/*.repo || true
fi

log "DNF refresh"
$SUDO "${DNF_BASE[@]}" clean all || true
$SUDO "${DNF_BASE[@]}" --refresh upgrade || true
$SUDO "${DNF_BASE[@]}" makecache || true

log "Fedora release: $(rpm -E %fedora)"

###############################################################################
# Build-Deps
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

  xorg-x11-server-Xwayland

  libxcb-devel xcb-util-devel xcb-util-wm-devel xcb-util-renderutil-devel xcb-util-image-devel xcb-util-keysyms-devel
  cairo-devel pango-devel
  glib2-devel
  hwdata
)

log "Install build dependencies"
$SUDO "${DNF_BASE[@]}" install "${BUILD_DEPS[@]}"
$SUDO "${DNF_BASE[@]}" install mesa-libGLES-devel || true

if [[ "${EXTRAS}" == "1" ]]; then
  log "Install extras (kitty + qt6ct)"
  $SUDO "${DNF_BASE[@]}" install kitty qt6ct
fi

###############################################################################
# Helpers
###############################################################################
clean_buildroot() {
  $SUDO rm -rf "${BUILDROOT}"
  $SUDO mkdir -p "${BUILDROOT}"
}

checkout_tag_or_vtag() {
  # usage: checkout_tag_or_vtag <tag>
  local t="$1"
  git fetch --tags --force
  if git rev-parse -q --verify "refs/tags/${t}" >/dev/null; then
    git checkout "refs/tags/${t}"
  elif git rev-parse -q --verify "refs/tags/v${t}" >/dev/null; then
    git checkout "refs/tags/v${t}"
  else
    return 1
  fi
}

build_wlroots_019() {
  log "Build & install wlroots ${WLROOTS_TAG}"
  rm -rf wlroots
  git clone https://gitlab.freedesktop.org/wlroots/wlroots.git wlroots
  cd wlroots
  if ! checkout_tag_or_vtag "${WLROOTS_TAG}"; then
    echo "ERROR: wlroots tag '${WLROOTS_TAG}' not found." >&2
    exit 1
  fi
  meson setup --wipe build -Dprefix=/usr -Dbuildtype=release -Dexamples=false
  ninja -C build
  $SUDO ninja -C build install
  $SUDO ldconfig
  cd "${BUILDROOT}"
}

build_scenefx_04() {
  log "Build & install scenefx ${SCENEFX_TAG}"
  rm -rf scenefx
  git clone https://github.com/wlrfx/scenefx.git scenefx
  cd scenefx
  if ! checkout_tag_or_vtag "${SCENEFX_TAG}"; then
    echo "ERROR: scenefx tag '${SCENEFX_TAG}' not found." >&2
    exit 1
  fi
  meson setup --wipe build -Dprefix=/usr -Dbuildtype=release
  ninja -C build
  $SUDO ninja -C build install
  $SUDO ldconfig
  cd "${BUILDROOT}"
}

get_mango_release_tags() {
  # Liefert tag_name Zeilen (neu -> alt). Wir nehmen N Releases.
  curl -fsSL "https://api.github.com/repos/DreamMaoMao/mangowc/releases?per_page=${MANGO_RELEASE_TRIES}" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

try_build_mango_tag() {
  local tag="$1"

  log "Try MangoWC release: ${tag}"
  rm -rf mangowc
  git clone https://github.com/DreamMaoMao/mangowc.git mangowc
  cd mangowc

  if ! checkout_tag_or_vtag "${tag}"; then
    log "Tag ${tag} not found in git tags (skip)"
    cd "${BUILDROOT}"
    return 1
  fi

  meson setup --wipe build -Dprefix=/usr -Dbuildtype=release

  # Build attempt (log for debugging)
  if ! ninja -C build 2>&1 | tee /tmp/mangowc_ninja.log; then
    # typischer Inkompatibilitätsmarker: Header fehlt
    if grep -q "wlr/types/wlr_drm_lease_v1.h" /tmp/mangowc_ninja.log; then
      log "Incompatible with wlroots-0.19 (missing wlr_drm_lease_v1.h). Trying older MangoWC..."
    else
      log "Build failed (not the drm_lease header). Trying older MangoWC anyway..."
    fi
    cd "${BUILDROOT}"
    return 1
  fi

  $SUDO ninja -C build install
  $SUDO ldconfig
  cd "${BUILDROOT}"
  log "SUCCESS: MangoWC ${tag} installed"
  return 0
}

###############################################################################
# Main
###############################################################################
log "Prepare build root: ${BUILDROOT}"
clean_buildroot
cd "${BUILDROOT}"

# Fixierte stabile Basis
build_wlroots_019
build_scenefx_04

log "Fetching MangoWC release tags (up to ${MANGO_RELEASE_TRIES})"
mapfile -t MANGO_TAGS < <(get_mango_release_tags)

if [[ "${#MANGO_TAGS[@]}" -eq 0 ]]; then
  echo "ERROR: Could not fetch MangoWC releases from GitHub API." >&2
  exit 1
fi

log "Trying MangoWC releases until one builds with wlroots ${WLROOTS_TAG}"
INSTALLED_TAG=""
for t in "${MANGO_TAGS[@]}"; do
  if try_build_mango_tag "${t}"; then
    INSTALLED_TAG="${t}"
    break
  fi
done

if [[ -z "${INSTALLED_TAG}" ]]; then
  echo "ERROR: None of the last ${MANGO_RELEASE_TRIES} MangoWC releases built against wlroots ${WLROOTS_TAG}." >&2
  echo "Tip: increase MANGO_RELEASE_TRIES, or switch strategy (Mango master + matching wlroots)." >&2
  exit 1
fi

###############################################################################
# Cleanup
###############################################################################
log "Cleanup build dir"
cd /
$SUDO rm -rf "${BUILDROOT}" || true
$SUDO rm -f /tmp/mangowc_ninja.log || true

if [[ "${SLIM}" == "1" ]]; then
  log "Slim mode: remove build deps"
  $SUDO "${DNF_BASE[@]}" remove "${BUILD_DEPS[@]}" || true
  $SUDO "${DNF_BASE[@]}" remove mesa-libGLES-devel || true
  $SUDO "${DNF_BASE[@]}" autoremove || true
  $SUDO "${DNF_BASE[@]}" clean all || true
else
  log "Slim mode disabled: keeping build deps"
fi

log "DONE: MangoWC installed (tag: ${INSTALLED_TAG}). Binary should be at /usr/bin/mangowc"
