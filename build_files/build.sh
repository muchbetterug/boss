#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# setup.sh — MangoWC on Bluefin/uBlue (buildah-friendly, "works in practice")
#
# What this script does:
# - Installs your COPR packages (niri+dms, noctalia, ghostty) + extras (kitty, qt6ct)
# - Builds MangoWC from the latest GitHub RELEASE tag (default) or master (optional)
# - Builds wlroots in a way that *actually works* on Fedora 42/Bluefin:
#     1) Try wlroots RELEASE tag 0.19.2 (fast path)
#     2) If MangoWC fails due to missing wlr_drm_lease_v1.h, rebuild wlroots from master
#        with Meson wrap fallback enabled to satisfy libdrm >= 2.4.129 requirements
# - Builds scenefx 0.4.1 (stable) by default
# - Optional slimming (remove build deps) at the end
#
# Tunables:
#   MANGO_CHANNEL=release|git    (default: release)
#   WLROOTS_RELEASE_TAG=0.19.2   (default: 0.19.2)
#   SCENEFX_REF=0.4.1            (default: 0.4.1)
#   SLIM=1                       (default: 1)
###############################################################################

log() { echo -e "\n==> $*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

# non-interactive git
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

# best-effort strip CRLF
$SUDO sed -i 's/\r$//' "$0" 2>/dev/null || true

# settings
MANGO_CHANNEL="${MANGO_CHANNEL:-release}"        # release | git
WLROOTS_RELEASE_TAG="${WLROOTS_RELEASE_TAG:-0.19.2}"
SCENEFX_REF="${SCENEFX_REF:-0.4.1}"
SLIM="${SLIM:-1}"

# Disable broken updates-archive repo if present (some uBlue layers)
if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then
  log "Disabling broken repo: updates-archive"
  $SUDO sed -i '/^\[updates-archive\]/,/^\[/{s/^\(enabled\s*=\s*\)1/\10/}' /etc/yum.repos.d/*.repo || true
fi

DNF_BASE=(dnf5 -y --disablerepo=updates-archive)

log "DNF cleanup/refresh"
$SUDO "${DNF_BASE[@]}" clean all || true
$SUDO "${DNF_BASE[@]}" --refresh upgrade || true
$SUDO "${DNF_BASE[@]}" makecache || true

FEDORA_VERSION="$(rpm -E %fedora)"
log "Fedora release: ${FEDORA_VERSION}"
log "Mango channel: ${MANGO_CHANNEL}"
log "wlroots release tag (first try): ${WLROOTS_RELEASE_TAG}"
log "scenefx ref: ${SCENEFX_REF}"
log "slim: ${SLIM}"

###############################################################################
# COPR installs (safe enable -> install -> disable)
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
# Build deps (arrays: no "\" pitfalls)
###############################################################################
BUILD_DEPS=(
  git curl
  gcc gcc-c++
  meson ninja-build
  pkgconf-pkg-config
  cmake

  wayland-devel wayland-protocols-devel
  libxkbcommon-devel
  pixman-devel
  libdrm-devel
  mesa-libEGL-devel mesa-libgbm-devel
  libinput-devel
  libseat-devel
  systemd-devel

  # Useful for wlroots builds on Fedora
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
# Resolve MangoWC ref
###############################################################################
resolve_mangowc_ref() {
  if [[ "${MANGO_CHANNEL}" == "git" ]]; then
    echo "master"
    return 0
  fi

  # release
  local ref
  ref="$(
    curl -fsSL "https://api.github.com/repos/DreamMaoMao/mangowc/releases/latest" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n1
  )"
  if [[ -z "${ref}" ]]; then
    echo ""
    return 1
  fi
  echo "${ref}"
}

log "Resolving MangoWC ref"
MANGOWC_REF="$(resolve_mangowc_ref)" || true
if [[ -z "${MANGOWC_REF}" ]]; then
  echo "ERROR: Could not resolve MangoWC release via GitHub API. Set MANGO_CHANNEL=git or try again." >&2
  exit 1
fi
log "MangoWC ref: ${MANGOWC_REF}"

###############################################################################
# Build functions
###############################################################################
BUILDROOT="/tmp/mangowc-build"
MANGO_BUILD_DIR=""

clean_buildroot() {
  $SUDO rm -rf "${BUILDROOT}"
  $SUDO mkdir -p "${BUILDROOT}"
}

checkout_tag_or_vtag() {
  # args: <taglike>
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

build_wlroots_release() {
  local tag="$1"
  log "Build wlroots (release tag: ${tag})"
  rm -rf wlroots
  git clone https://gitlab.freedesktop.org/wlroots/wlroots.git wlroots
  cd wlroots
  if ! checkout_tag_or_vtag "${tag}"; then
    echo "ERROR: wlroots tag '${tag}' not found." >&2
    echo "Available tags (last 30):" >&2
    git tag --list | tail -n 30 >&2
    exit 1
  fi
  meson setup build -Dprefix=/usr -Dbuildtype=release -Dexamples=false
  ninja -C build
  $SUDO ninja -C build install
  $SUDO ldconfig
  cd "${BUILDROOT}"
}

build_wlroots_master_with_wrapfallback() {
  log "Build wlroots (master) with Meson wrap fallback (for newer deps like libdrm>=2.4.129)"

  rm -rf wlroots
  git clone --depth 1 https://gitlab.freedesktop.org/wlroots/wlroots.git wlroots
  cd wlroots

  # GCC 15 hits Werror in libdrm wrap. Keep this scoped to this build only.
  local saved_cflags="${CFLAGS:-}"
  local saved_cxxflags="${CXXFLAGS:-}"

  export CFLAGS="${saved_cflags} -Wno-error"
  export CXXFLAGS="${saved_cxxflags}"

  meson setup build \
    -Dprefix=/usr \
    -Dbuildtype=release \
    -Dexamples=false \
    --wrap-mode=default

  ninja -C build
  $SUDO ninja -C build install
  $SUDO ldconfig

  export CFLAGS="${saved_cflags}"
  export CXXFLAGS="${saved_cxxflags}"

  cd "${BUILDROOT}"
}

build_scenefx() {
  local ref="$1"
  log "Build scenefx (${ref})"
  rm -rf scenefx
  git clone https://github.com/wlrfx/scenefx.git scenefx
  cd scenefx
  if [[ "${ref}" == "master" ]]; then
    git checkout master || true
    git pull --ff-only || true
  else
    if ! checkout_tag_or_vtag "${ref}"; then
      echo "ERROR: scenefx tag '${ref}' not found." >&2
      echo "Available tags (last 30):" >&2
      git tag --list | tail -n 30 >&2
      exit 1
    fi
  fi
  meson setup build -Dprefix=/usr -Dbuildtype=release
  ninja -C build
  $SUDO ninja -C build install
  $SUDO ldconfig
  cd "${BUILDROOT}"
}

build_mangowc() {
  local ref="$1"
  log "Build mangowc (${ref})"
  rm -rf mangowc
  git clone https://github.com/DreamMaoMao/mangowc.git mangowc
  cd mangowc
  if [[ "${ref}" == "master" ]]; then
    git checkout master || true
    git pull --ff-only || true
  else
    if ! checkout_tag_or_vtag "${ref}"; then
      echo "ERROR: mangowc tag '${ref}' not found in repo tags." >&2
      echo "Available tags (last 30):" >&2
      git tag --list | tail -n 30 >&2
      exit 1
    fi
  fi

  # build
  meson setup build -Dprefix=/usr -Dbuildtype=release
  # capture build log to detect the known wlroots mismatch
  if ! ninja -C build 2>&1 | tee /tmp/mangowc_ninja.log; then
    return 1
  fi
  $SUDO ninja -C build install
  $SUDO ldconfig
  cd "${BUILDROOT}"
  return 0
}

###############################################################################
# Main build flow
###############################################################################
log "Prepare build root: ${BUILDROOT}"
clean_buildroot
cd "${BUILDROOT}"

# 1) Try stable-ish path first: wlroots release + scenefx release + mangowc (release or master)
build_wlroots_release "${WLROOTS_RELEASE_TAG}"
build_scenefx "${SCENEFX_REF}"

if build_mangowc "${MANGOWC_REF}"; then
  log "MangoWC build succeeded with wlroots ${WLROOTS_RELEASE_TAG}"
else
  # Check for the specific header-missing error that indicates wlroots too old
  if grep -q "wlr/types/wlr_drm_lease_v1.h" /tmp/mangowc_ninja.log; then
    log "Detected missing wlr_drm_lease_v1.h => wlroots too old. Rebuilding wlroots from master with wrap fallback."
    build_wlroots_master_with_wrapfallback

    # scenefx should match newer wlroots more reliably when on master too.
    # If you want to keep scenefx pinned, set SCENEFX_REF=0.4.1 (default) and we'll try it first,
    # but if mangowc still fails later, switching scenefx to master is the common fix.
    if [[ "${SCENEFX_REF}" != "master" ]]; then
      log "Rebuilding scenefx on master to match wlroots master"
      build_scenefx "master"
    fi

    # retry mangowc
    if ! build_mangowc "${MANGOWC_REF}"; then
      echo "ERROR: mangowc still failed after upgrading wlroots (master + wrap fallback)." >&2
      echo "See /tmp/mangowc_ninja.log for details." >&2
      exit 1
    fi
    log "MangoWC build succeeded with wlroots master (wrap fallback)"
  else
    echo "ERROR: mangowc failed for a reason other than the known wlroots header mismatch." >&2
    echo "See /tmp/mangowc_ninja.log for details." >&2
    exit 1
  fi
fi

###############################################################################
# Cleanup build directory
###############################################################################
log "Cleanup build directory"
cd /
$SUDO rm -rf "${BUILDROOT}" || true
$SUDO rm -f /tmp/mangowc_ninja.log || true

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
