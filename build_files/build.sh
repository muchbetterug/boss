#!/bin/bash
set -ouex pipefail

# 1) Niri + DMS (Copr)
dnf5 -y copr enable avengemedia/dms
dnf5 -y install niri dms
dnf5 -y copr disable avengemedia/dms

# 2) Noctalia (Copr)
dnf5 -y copr enable zhangyi6324/noctalia-shell
# Falls der Copr es nicht als Dependency zieht, quickshell explizit mitinstallieren:s
dnf5 -y install noctalia-shell quickshell || dnf5 -y install noctalia-shell
dnf5 -y copr disable zhangyi6324/noctalia-shell

dnf5 -y copr enable scottames/ghostty
dnf5 -y install ghostty
dnf5 -y copr disable scottames/ghostty

dnf5 -y install kitty
dnf5 -y install qt6ct # für icons

dnf5 -y install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
dnf5 -y update
dnf5 -y install mangowc

# 3) Niri systemweite Default-Config setzen:
# Niri lädt config.kdl aus ~/.config/niri/… und fällt sonst auf /etc/niri/config.kdl zurück. :contentReference[oaicite:2]{index=2}
#install -d /etc/niri

#cat >/etc/niri/config.kdl <<'KDL'
#include "./boss.kdl"
#KDL

#cat >/etc/niri/boss.kdl <<'KDL'
#layout {
#    center-focused-column "always"
#    gaps 8

#    focus-ring {
#        off
#    }

#    preset-column-widths {
#        proportion 0.25
#        proportion 0.33333
#        proportion 0.5
#        proportion 0.66667
#    }
#}

#prefer-no-csd
#screenshot-path "~/Bilder/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"
#spawn-at-startup "noctalia-shell"
#KDL
