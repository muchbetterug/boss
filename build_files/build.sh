#!/usr/bin/env bash
set -euo pipefail

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

# Terra-Release-Paket herunterladen und installieren
dnf5 install -y https://repos.fyralabs.com/terra${FEDORA_VERSION}/terra-release-${FEDORA_VERSION}-1.noarch.rpm
