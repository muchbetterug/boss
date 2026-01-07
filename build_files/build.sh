#!/usr/bin/env bash
set -euo pipefail

# Bluefin/uBlue: Hyprland + hyprscroller (PaperWM-like, mouse-first)
# Noctalia Shell as full shell on top of Hyprland
# GDM is used (default Bluefin)

log() { echo -e "\n==> $*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

# Disable broken updates-archive repo if present
if grep -Rqs "^\[updates-archive\]" /etc/yum.repos.d; then
  log "Disable broken repo: updates-archive"
  $SUDO sed -i '/^\[updates-archive\]/,/^\[/{s/^\(enabled\s*=\s*\)1/\10/}' /etc/yum.repos.d/*.repo
fi

DNF=(dnf5 -y --disablerepo=updates-archive)

log "Refresh repos"
$SUDO "${DNF[@]}" clean all
$SUDO "${DNF[@]}" --refresh upgrade || true
$SUDO "${DNF[@]}" makecache

log "Install COPR plugin"
$SUDO "${DNF[@]}" install dnf5-plugins

# --- Hyprland core ---
log "Install Hyprland + portals"
$SUDO "${DNF[@]}" install \
  hyprland \
  xdg-desktop-portal-hyprland \
  foot rofi \
  wl-clipboard \
  grim slurp \
  swaylock \
  xdg-user-dirs \
  adwaita-icon-theme

# --- Noctalia Shell ---
log "Enable COPR: zhangyi6324/noctalia-shell"
$SUDO "${DNF[@]}" copr enable zhangyi6324/noctalia-shell

log "Install Noctalia Shell + quickshell"
$SUDO "${DNF[@]}" install noctalia-shell quickshell

# --- hyprscroller bootstrap (per-user via hyprpm) ---
log "Install hyprscroller bootstrap helper"
$SUDO install -Dm0755 /dev/stdin /usr/local/bin/hyprscroller-bootstrap <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

command -v hyprpm >/dev/null 2>&1 || exit 0

if hyprpm list | grep -qi hyprscroller; then
  hyprpm reload -n || true
  exit 0
fi

hyprpm add https://github.com/dawsers/hyprscroller
hyprpm enable hyprscroller
hyprpm reload -n || true
EOF

# --- Default Hyprland config (PaperWM mouse workflow) ---
log "Write /etc/skel Hyprland config (PaperWM-style, mouse-first)"
$SUDO install -d /etc/skel/.config/hypr

$SUDO install -Dm0644 /dev/stdin /etc/skel/.config/hypr/hyprland.conf <<'EOF'
# ======================================================
# Hyprland + hyprscroller
# PaperWM-like layout (mouse-centric desktop workflow)
# Noctalia = full shell
# ======================================================

$mainMod = SUPER

# --- IMPORTANT: disable native swipe, scroller replaces it ---
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

# --- Start shell ---
exec-once = noctalia-shell
exec-once = /usr/local/bin/hyprscroller-bootstrap

# Keep active column centered (PaperWM core behavior)
exec-once = hyprctl dispatch scroller:setmode center_column

# --- Apps ---
bind = $mainMod, Return, exec, foot
bind = $mainMod, D, exec, rofi -show drun
bind = $mainMod, Q, killactive
bind = $mainMod, F, fullscreen, 1

# ======================================================
# PaperWM MOUSE WORKFLOW
# ======================================================

# Scroll horizontally through columns (SUPER + wheel)
bind = $mainMod, mouse_down, movefocus, r
bind = $mainMod, mouse_up, movefocus, l

# Reorder windows by scrolling (SUPER+SHIFT + wheel)
bind = $mainMod SHIFT, mouse_down, movewindow, r
bind = $mainMod SHIFT, mouse_up, movewindow, l

# Grab window with mouse (like PaperWM drag)
bindm = $mainMod, mouse:272, movewindow

# Resize with mouse
bindm = $mainMod SHIFT, mouse:272, resizewindow

# Overview (PaperWM style)
bind = $mainMod, Tab, scroller:toggleoverview

# Screenshots
bind = , Print, exec, grim -g "$(slurp)" - | wl-copy
EOF

log "Done: Hyprland + hyprscroller + Noctalia (GDM-ready)"
log "Select 'Hyprland' session in GDM gear menu."
