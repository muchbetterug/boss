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

# Scroll via COPR installieren
dnf -y copr enable scrollwm/packages
dnf install -y scroll
dnf -y copr disable scrollwm/packages

# DMS installieren
dnf -y copr enable avengemedia/dms
dnf install -y dms
dnf -y copr disable avengemedia/dms

# Dankinstall (für post-install Setup von DMS) – direkt aus GitHub Release
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)       echo "Unsupported architecture: $ARCH" && exit 1 ;;
esac

LATEST_VERSION=$(curl -s https://api.github.com/repos/AvengeMedia/DankMaterialShell/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

curl -L "https://github.com/AvengeMedia/DankMaterialShell/releases/download/${LATEST_VERSION}/dankinstall-${ARCH}.gz" -o /usr/bin/dankinstall.gz
gunzip /usr/bin/dankinstall.gz
chmod +x /usr/bin/dankinstall

# DMS-Konfiguration für neue User (Skeleton)
git clone https://github.com/AvengeMedia/DankMaterialShell.git /etc/skel/.config/DankMaterialShell

# Hyprland: DMS automatisch starten
mkdir -p /etc/skel/.config/hypr
cat <<EOF > /etc/skel/.config/hypr/hyprland.conf
exec-once = dms
EOF

# Niri: DMS automatisch starten
mkdir -p /etc/skel/.config/niri
cat <<EOF > /etc/skel/.config/niri/config.kdl
spawn "dms"
EOF

# Podman Socket aktivieren
systemctl enable podman.socket
