#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Bluefin/uBlue (Fedora): Hyprland + hyprscrolling (PaperWM-like via scroller layout)
#           + Noctalia Shell (+ quickshell)
#
# Bluefin image notes:
# - Build runs as root → no sudo.
# - Avoid /usr/local; use /usr/bin or /usr/libexec.
# - hyprscrolling is enabled per-user via hyprpm on first Hyprland start (needs network once).
# - Seed Noctalia + Hyprland config into /etc/skel for new users.

log() { echo -e "\n==> $*"; }

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run this script as root (image build context)." >&2
  exit 1
fi

# Bluefin/uBlue: sometimes "updates-archive" repo is broken (404). Disable it (harmless if not present).
if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d 2>/dev/null; then
  log "Disable broken repo: updates-archive"
  sed -i '/^\[updates-archive\]/,/^\[/{s/^\(enabled\s*=\s*\)1/\10/}' /etc/yum.repos.d/*.repo || true
fi

DNF=(dnf5 -y --disablerepo=updates-archive)

log "Refresh repos"
"${DNF[@]}" clean all
"${DNF[@]}" --refresh upgrade || true
"${DNF[@]}" makecache

log "Install COPR plugin (dnf5-plugins)"
"${DNF[@]}" install dnf5-plugins

# -----------------------------
# Hyprland + essentials (+ plugin build deps for hyprpm)
# -----------------------------
log "Install Hyprland + portals + essentials + build deps for hyprpm plugins"
"${DNF[@]}" install \
  git \
  gcc-c++ \
  ninja-build \
  pkgconf-pkg-config \
  make \
  cmake \
  meson \
  cpio \
  \
  hyprland \
  xdg-desktop-portal-hyprland \
  \
  foot rofi \
  wl-clipboard \
  grim slurp \
  swaylock \
  xdg-user-dirs \
  adwaita-icon-theme \
  \
  mesa-libGL-devel \
  mesa-libEGL-devel \
  mesa-libGLES-devel \
  libdrm-devel \
  wayland-devel \
  libxkbcommon-devel \
  pixman-devel

# Optional niceties (do not fail build if unavailable)
"${DNF[@]}" install wayland-utils xorg-x11-xauth || true

# -----------------------------
# Noctalia Shell (+ quickshell) via COPR
# -----------------------------
log "Enable COPR: zhangyi6324/noctalia-shell"
"${DNF[@]}" copr enable zhangyi6324/noctalia-shell

log "Install Noctalia Shell + quickshell"
"${DNF[@]}" install noctalia-shell quickshell

# -----------------------------
# hyprscrolling bootstrap helper (per-user via hyprpm)
# -----------------------------
log "Install hyprscrolling bootstrap helper (/usr/bin/hyprplugins-bootstrap)"
install -Dm0755 /dev/stdin /usr/bin/hyprplugins-bootstrap <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

command -v hyprpm >/dev/null 2>&1 || exit 0

# only useful inside a Hyprland session
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  exit 0
fi

# hyprscrolling lives in hyprwm/hyprland-plugins
hyprpm add https://github.com/hyprwm/hyprland-plugins || true
hyprpm enable hyprscrolling || true

# keep it best-effort; don't break login if something is off
hyprpm update || true
hyprpm reload -n || true
EOF

# -----------------------------
# Seed Noctalia config into /etc/skel (best-effort)
# -----------------------------
log "Seed Noctalia config into /etc/skel (best-effort)"
install -d /etc/skel/.config
env HOME=/etc/skel noctalia-shell --copy --force || true

# -----------------------------
# Default Hyprland config for new users (/etc/skel)
# -----------------------------
log "Write /etc/skel Hyprland config (PaperWM-style, mouse-first, Noctalia full shell)"
install -d /etc/skel/.config/hypr

install -Dm0644 /dev/stdin /etc/skel/.config/hypr/hyprland.conf <<'EOF'
# ======================================================
# Hyprland + hyprscrolling (PaperWM-like via "scroller" layout)
# Mouse-centric workflow + Noctalia as full shell
# ======================================================

$mainMod = SUPER

gestures {
  # Hyprland swipe can conflict with scroller behavior
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
# Startup: Polkit + Noctalia + hyprscrolling bootstrap
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

# Install/enable hyprscrolling per-user (hyprpm is per-home)
exec-once = /usr/bin/hyprplugins-bootstrap

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

# Drag window with mouse
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod SHIFT, mouse:272, resizewindow

# Overview (provided by hyprscrolling)
bind = $mainMod, Tab, scroller:toggleoverview

# Screenshots (copy selection to clipboard)
bind = , Print, exec, grim -g "$(slurp)" - | wl-copy
EOF

log "Done: Hyprland + hyprscrolling + Noctalia (GDM-ready)"
log "GDM: choose session 'Hyprland' via the gear icon on the login screen."
log "Note: hyprscrolling installs/enables on first Hyprland start (needs network once)."
