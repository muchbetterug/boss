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

# 3) Niri systemweite Default-Config setzen:
# Niri lädt config.kdl aus ~/.config/niri/… und fällt sonst auf /etc/niri/config.kdl zurück. :contentReference[oaicite:2]{index=2}
install -d /etc/niri

cat >/etc/niri/config.kdl <<'KDL'
# Minimal: keine doppelte Bar (Default-config startet oft Waybar) :contentReference[oaicite:3]{index=3}

# Starte DMS + Noctalia beim Session-Start.
# (DMS besser so als per systemd-service, da es dort IPC-Probleme geben kann.) :contentReference[oaicite:4]{index=4}
spawn-at-startup "noctalia-shell"

include "./boss.kdl"
KDL

cat >/etc/niri/boss.kdl <<'KDL'
layout {
    center-focused-column "always"
    gaps 8

    focus-ring {
        off
    }

    preset-column-widths {
        proportion 0.25
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }
}

prefer-no-csd
screenshot-path "~/Bilder/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"
KDL
