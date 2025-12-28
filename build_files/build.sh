#!/bin/bash

set -ouex pipefail

# Hyprland via COPR installieren
dnf -y copr enable solopasha/hyprland
dnf install -y hyprland
dnf -y copr disable solopasha/hyprland

# Niri via COPR installieren
dnf -y copr enable yalter/niri
dnf install -y niri
dnf -y copr disable yalter/niri

# DMS installieren
dnf -y copr enable avengemedia/dms
dnf install -y dms
dnf -y copr disable avengemedia/dms

# COSMIC via COPR installieren
dnf -y copr enable ryanabx/cosmic-epoch
dnf install -y cosmic-desktop
dnf -y copr disable ryanabx/cosmic-epoch

# Scroll via COPR installieren
dnf -y copr enable scrollwm/packages
dnf install -y scroll
dnf -y copr disable scrollwm/packages

# MangoWC via Terra Repository installieren
dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
dnf install -y mangowc

# DMS-Konfiguration für neue User
git clone https://github.com/AvengeMedia/DankMaterialShell.git /etc/skel/.config/DankMaterialShell

# Hyprland-Config anpassen (DMS-Start)
mkdir -p /etc/skel/.config/hypr
echo "exec-once = dms" >> /etc/skel/.config/hypr/hyprland.conf

# Niri-Config anpassen (DMS-Start)
mkdir -p /etc/skel/.config/niri
echo 'spawn "dms"' >> /etc/skel/.config/niri/config.kdl

# COSMIC-Config anpassen (DMS-Start, Kompatibilität prüfen)
mkdir -p /etc/skel/.config/cosmic
echo "exec-once = dms" >> /etc/skel/.config/cosmic/config.toml

# Scroll-Config anpassen (DMS-Start, Kompatibilität prüfen)
mkdir -p /etc/skel/.config/scroll
echo "exec dms" >> /etc/skel/.config/scroll/config

# MangoWC-Config anpassen (DMS-Start, Kompatibilität prüfen)
mkdir -p /etc/skel/.config/mango
echo "exec dms" >> /etc/skel/.config/mango/config

# Beispiel: System Unit aktivieren
systemctl enable podman.socket
