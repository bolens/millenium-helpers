FROM archlinux:latest

# Install dependencies needed for development, linting, and testing
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    git \
    curl \
    jq \
    python \
    python-pip \
    shellcheck \
    ruff \
    sudo \
    systemd \
    unzip \
    zsh \
    fish \
    nushell

# Create a developer user who is in the wheel group for passwordless sudo testing
RUN useradd -m -g wheel -s /bin/bash developer && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/etc/sudoers || echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Create mock Steam and Flatpak folders to facilitate sandbox diagnostics and testing
RUN mkdir -p /home/developer/.local/share/Steam/steamui/skins && \
    mkdir -p /home/developer/.config/systemd/user && \
    chown -R developer:wheel /home/developer

USER developer
WORKDIR /workspace
