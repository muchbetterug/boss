#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Bluefin/uBlue (Fedora): Hyprland + hyprscroller (PaperWM-like) + Noctalia Shell (+ quickshell)
# Notes for Bluefin images:
# - Avoid writing to /usr/local (can be special/immutable); use /usr/bin or /usr/libexec instead.
# - hyprscroller is installed per-user via hyprpm at first Hyprland start (needs network once).
# - Seed Noctalia config into /etc/skel so new users get "full shell" OOTB.

log() { echo -e "\n==> $*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

# Bluefin/uBlue: sometimes "updates-archive" repo is broken (404). Disable it hard (harmless if not present).
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

# -----------------------------
# Hyprland + essentials
# -----------------------------
log "Install Hyprland + portals + essentials"
$SUDO "${DNF[@]}" install \
gcc-c++ \
ninja-build \
pkgconf-pkg-config \
make \
cmake \
meson \
cpio \
hyprland \
xdg-desktop-portal-hyprland \
foot rofi \
wl-clipboard \
grim slurp \
swaylock \
xdg-user-dirs \
adwaita-icon-theme

# Optional niceties (do not fail build if unavailable)
$SUDO "${DNF[@]}" install \
  wayland-utils \
  xorg-x11-xauth \
  || true

# -----------------------------
# Noctalia Shell (+ quickshell) via COPR
# -----------------------------
log "Enable COPR: zhangyi6324/noctalia-shell"
$SUDO "${DNF[@]}" copr enable zhangyi6324/noctalia-shell

log "Install Noctalia Shell + quickshell"
$SUDO "${DNF[@]}" install noctalia-shell quickshell

# -----------------------------
# Polkit agent (reliable with Hyprland)
# -----------------------------
# Noctalia COPR already pulled polkit-kde in your logs, but we ensure it exists.
#log "Install polkit agent (polkit-kde)"
#$SUDO "${DNF[@]}" install polkit-kde

# -----------------------------
# hyprscroller bootstrap helper (per-user via hyprpm)
# DO NOT use /usr/local on Bluefin images
# -----------------------------
#log "Install hyprscroller bootstrap helper (/usr/bin)"
#$SUDO install -Dm0755 /dev/stdin /usr/bin/hyprscroller-bootstrap <<'EOF'
##!/usr/bin/env bash
#set -euo pipefail

# Runs inside a Hyprland session (exec-once).
# Installs & enables hyprscroller via hyprpm if missing, then reloads plugins.

#command -v hyprpm >/dev/null 2>&1 || exit 0

# Already installed?
#if hyprpm list 2>/dev/null | grep -qi hyprscroller; then
#  hyprpm reload -n || true
#  exit 0
#fi

# PaperWM-like scrolling layout plugin
#hyprpm add https://github.com/dawsers/hyprscroller
#hyprpm enable hyprscroller
#hyprpm reload -n || true
#EOF

# -----------------------------
# Seed Noctalia config into /etc/skel so new users get full shell OOTB
# (Noctalia itself recommends: noctalia-shell --copy)
# We "fake" HOME=/etc/skel during build. If it fails in container, don't break the build.
# -----------------------------
log "Seed Noctalia config into /etc/skel (best-effort)"
$SUDO install -d /etc/skel/.config
$SUDO env HOME=/etc/skel noctalia-shell --copy --force || true

# -----------------------------
# TOOOOODOOO GEHJT NICHT Default Hyprland config (PaperWM mouse-centric)
# -----------------------------
log "Write /etc/skel Hyprland config (PaperWM-style, mouse-first, Noctalia full shell)"
$SUDO install -d /etc/skel/.config/hypr

$SUDO install -Dm0644 /dev/stdin /etc/skel/.config/hypr/hyprland.conf <<'EOF'
# ======================================================
# Hyprland + hyprscroller (PaperWM-like)
# Desktop / mouse-centric workflow
# Noctalia Shell as full shell
# ======================================================

$mainMod = SUPER

# If Hyprland's swipe is on, it can conflict with scroller behavior.
gestures {
  workspace_swipe = off
}

general {
  layout = scroller
  gaps_in = 6
  gaps_out = 10
  border_size = 2
}

decoration {
  rounding = 10
}

input {
  follow_mouse = 1
}

# ------------------------------------------------------
# Startup: Polkit + Noctalia + hyprscroller bootstrap
# ------------------------------------------------------

# Polkit agent (choose the first existing path)
exec-once = sh -lc 'for a in \
  /usr/libexec/polkit-kde-authentication-agent-1 \
  /usr/lib/polkit-kde-authentication-agent-1 \
  /usr/libexec/lxqt-policykit-agent; do \
    [ -x "$a" ] && exec "$a"; \
  done'

# Noctalia full shell
exec-once = noctalia-shell

# Install/enable hyprscroller per-user (hyprpm is per-home)
exec-once = /usr/bin/hyprscroller-bootstrap

# Center active column (PaperWM core feel)
exec-once = hyprctl dispatch scroller:setmode center_column

# ------------------------------------------------------
# Apps / basics
# ------------------------------------------------------
bind = $mainMod, Return, exec, foot
bind = $mainMod, D, exec, rofi -show drun
bind = $mainMod, Q, killactive
bind = $mainMod, F, fullscreen, 1

# ------------------------------------------------------
# PaperWM-like mouse workflow
# ------------------------------------------------------

# Scroll horizontally through columns (SUPER + wheel)
bind = $mainMod, mouse_down, movefocus, r
bind = $mainMod, mouse_up, movefocus, l

# Reorder windows by scrolling (SUPER+SHIFT + wheel)
bind = $mainMod SHIFT, mouse_down, movewindow, r
bind = $mainMod SHIFT, mouse_up, movewindow, l

# Drag window with mouse (closest practical to "drag titlebar to reorder")
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod SHIFT, mouse:272, resizewindow

# Overview
bind = $mainMod, Tab, scroller:toggleoverview

# Screenshots (copy selection to clipboard)
bind = , Print, exec, grim -g "$(slurp)" - | wl-copy
EOF

log "Done: Hyprland + hyprscroller + Noctalia (GDM-ready)"
log "GDM: choose session 'Hyprland' via the gear icon on the login screen."
log "Note: hyprscroller installs on first Hyprland start (needs network once)."
