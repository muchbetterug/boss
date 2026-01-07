#!/bin/bash
set -ouex pipefail

RELEASE="$(rpm -E %fedora)"

log() {
  echo "=== $* ==="
}

#######################################################################
# Setup Repositories
#######################################################################

log "Enable Copr repos..."
COPR_REPOS=(
    scrollwm/packages
    zhangyi6324/noctalia-shell
)

for repo in "${COPR_REPOS[@]}"; do
  # Try to enable the repo, but don't fail the build if it doesn't support this Fedora version
  if ! dnf5 -y copr enable "$repo" 2>&1; then
    log "Warning: Failed to enable COPR repo $repo (may not support Fedora $RELEASE)"
  fi
done

# Your error is a 404 from fedoraproject-updates-archive.* -> disable it hard
log "Disable Fedora updates-archive repos (404 in some base images)..."
dnf5 -y config-manager setopt '*updates-archive*.enabled=0' || true
dnf5 -y config-manager setopt '*-updates-archive.enabled=0' || true

# Refresh metadata/caches
log "Refresh dnf metadata..."
dnf5 clean all || true
rm -rf /var/cache/dnf /var/cache/libdnf5 || true
dnf5 makecache --refresh || true

#######################################################################
## Install Packages
#######################################################################

FONTS=(
  fira-code-fonts
  fontawesome-fonts-all
  google-noto-emoji-fonts
)

# Hyprland ecosystem packages
SCROLL_PKGS=(
    scroll
    noctalia-shell
    quickshell
)

# Special GUI apps that need to be installed at the system level.
ADDITIONAL_SYSTEM_APPS=(
  alacritty
  kitty
  kitty-terminfo
  thunar
  thunar-volman
  thunar-archive-plugin
)

log "Installing packages using dnf5..."
dnf5 install -y \
  --setopt=install_weak_deps=False \
  --setopt=ip_resolve=4 \
  --setopt=retries=20 \
  --setopt=timeout=60 \
  --disablerepo='*updates-archive*' \
  --skip-unavailable \
  "${FONTS[@]}" \
  "${SCROLL_PKGS[@]}" \
  "${ADDITIONAL_SYSTEM_APPS[@]}"

log "Disable Copr repos to get rid of clutter..."
for repo in "${COPR_REPOS[@]}"; do
  dnf5 -y copr disable "$repo" || true
done
