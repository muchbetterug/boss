#!/usr/bin/env bash
set -euo pipefail

# Bluefin build script helper
log() { echo -e "\n==> $*"; }

FEDORA_VERSION="$(rpm -E %fedora)"
TERRA_URL="https://repos.fyralabs.com/terra${FEDORA_VERSION}"

log "Fedora: ${FEDORA_VERSION}"
log "Terra URL: ${TERRA_URL}"

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

# 5) Terra repo (terra-release)
log "Install terra-release via repofrompath (no \$releasever pitfalls)"
dnf5 -y install --nogpgcheck --repofrompath "terra,${TERRA_URL}" terra-release

log "Refresh metadata"
dnf5 -y clean all
dnf5 -y makecache

# 6) Check if mangowc exists
log "Check availability of mangowc"
if ! dnf5 -q repoquery mangowc >/dev/null 2>&1; then
  echo
  echo "ERROR: 'mangowc' is not available for Fedora ${FEDORA_VERSION} in the enabled repos."
  echo "       This matches that Terra${FEDORA_VERSION} does not appear to ship mangowc currently."
  echo
  echo "Options:"
  echo "  1) Build MangoWC from source (official docs include wlroots+scenefx pins)."
  echo "  2) Use a COPR that provides MangoWC (quality varies)."
  echo "  3) Use a Fedora version / image where the package is available."
  exit 1
fi

log "Install mangowc"
dnf5 -y install mangowc
