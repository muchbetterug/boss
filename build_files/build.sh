#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Bluefin/uBlue: MangoWC + Noctalia Shell (+ quickshell) via COPR
# Happy-path only: enable COPRs, install packages, done.

log() { echo -e "\n==> $*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

# Bluefin/uBlue: manchmal ist "updates-archive" kaputt (404). Hart deaktivieren (harmlos wenn nicht vorhanden).
if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then
  log "Disable broken repo: updates-archive"
  $SUDO sed -i '/^\[updates-archive\]/,/^\[/{s/^\(enabled\s*=\s*\)1/\10/}' /etc/yum.repos.d/*.repo
fi

DNF=(dnf5 -y --disablerepo=updates-archive)

log "Refresh repos"
$SUDO "${DNF[@]}" clean all
$SUDO "${DNF[@]}" --refresh upgrade || true
$SUDO "${DNF[@]}" makecache

log "Install COPR plugin (dnf5-plugins)"
$SUDO "${DNF[@]}" install dnf5-plugins

# --- MangoWC (COPR) ---
log "Enable COPR: dennemann/MangoWC"
$SUDO "${DNF[@]}" copr enable dennemann/MangoWC

log "Install MangoWC"
$SUDO "${DNF[@]}" install mangowc

# --- Noctalia Shell (+ quickshell) (COPR) ---
log "Enable COPR: zhangyi6324/noctalia-shell"
$SUDO "${DNF[@]}" copr enable zhangyi6324/noctalia-shell

log "Install Noctalia Shell + quickshell"
$SUDO "${DNF[@]}" install noctalia-shell quickshell

log "Done: mangowc + noctalia-shell + quickshell installed"
log "Hint: In a container, starting a compositor may require proper /dev/dri + seat/session setup at runtime."
