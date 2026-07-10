FROM archlinux:latest

# Install dependencies needed for development, linting, and testing.
# Stay root here so Dev Container features (PowerShell, Nix, DinD) can install cleanly;
# remoteUser in devcontainer.json switches to developer at runtime.
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    bash-completion \
    curl \
    git \
    github-cli \
    jq \
    mandoc \
    openssh \
    pre-commit \
    python \
    python-pip \
    ruff \
    shellcheck \
    sudo \
    systemd \
    unzip \
    which \
    zsh \
    fish \
    nushell && \
    pacman -Scc --noconfirm

# Create a developer user in the wheel group for passwordless sudo testing
RUN useradd -m -G wheel -s /bin/bash developer && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && \
    chmod 440 /etc/sudoers.d/wheel

# Mock Steam / systemd user dirs for sandbox diagnostics and testing
RUN mkdir -p /home/developer/.local/share/Steam/steamui/skins && \
    mkdir -p /home/developer/.config/systemd/user && \
    chown -R developer:developer /home/developer

WORKDIR /workspaces/millenium-helpers
