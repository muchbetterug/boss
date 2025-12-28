#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# Niri via COPR installieren
dnf5 -y copr enable yalter/niri
dnf5 install -y niri
dnf5 -y copr disable yalter/niri

# DankMaterialShell installieren
curl -fsSL https://install.danklinux.com | bash

# DankMaterialShell-Konfiguration für neue User vorinstallieren
git clone https://github.com/AvengeMedia/DankMaterialShell.git /etc/skel/.config/DankMaterialShell

# Hyprland via COPR installieren
#dnf5 -y copr enable solopasha/hyprland
#dnf5 install -y hyprland
#dnf5 -y copr disable solopasha/hyprland

# Abhängigkeiten für DankMaterialShell installieren
#dnf5 install -y quickshell matugen pywal cava gojq yq ripgrep wl-clipboard cliphist

# DankMaterialShell-Konfiguration für neue User vorinstallieren
#git clone https://github.com/AvengeMedia/DankMaterialShell.git /etc/skel/.config/DankMaterialShell

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket
