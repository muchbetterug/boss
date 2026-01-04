#!/bin/bash

set -ouex pipefail

# DMS installieren
dnf -y copr enable avengemedia/dms
dnf install -y niri dms
dnf -y copr disable avengemedia/dms

systemctl --user add-wants niri.service dms

# Podman Socket aktivieren
systemctl enable podman.socket
