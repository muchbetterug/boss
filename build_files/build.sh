#!/bin/bash

set -ouex pipefail

# DMS installieren
dnf5 -y copr enable avengemedia/dms
dnf5 install -y niri dms
dnf5 -y copr disable avengemedia/dms

systemctl --user add-wants niri.service dms

# Podman Socket aktvieren
# systemctl enable podman.socket

#change pretty name
sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"boss\"|" /usr/lib/os-release
