# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
# Bluefin "classic" (also nicht -dx) mit NVIDIA.
# Achtung, die Quelle hat sich verschoben: ghcr.io/projectbluefin/bluefin-nvidia ist am
# 17.09.2026 stehen geblieben (letzter Tag testing-44.20260917.5), dort kommt nichts mehr
# nach. Gepflegt wird wieder unter ublue-os, und die proprietäre Variante
# ghcr.io/ublue-os/bluefin-nvidia endete mit Fedora 42 -> übrig bleibt nvidia-open.
# Das ist für Turing und neuer der empfohlene Treiber, die RTX 4070 (Ada) fällt darunter.
FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable
#FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable-daily # täglich statt wochenweise gated
#FROM ghcr.io/ublue-os/bluefin-dx-nvidia-open:stable    # dasselbe als Developer-Variante
#FROM ghcr.io/ublue-os/bazzite:stable

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
#
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
