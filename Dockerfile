FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies, networking utilities, desktop, and XRDP
RUN apt-get update && apt-get install -y \
    curl \
    sudo \
    iptables \
    iproute2 \
    ethtool \
    net-tools \
    openssl \
    ca-certificates \
    dbus-x11 \
    xfce4 \
    xfce4-goodies \
    xorgxrdp \
    xrdp \
    firefox \
    && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Create runner user with passwordless sudo rights
RUN useradd -m -s /bin/bash runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    adduser xrdp ssl-cert

# Optimize XRDP for lower latency
RUN sed -i 's/max_bpp=32/max_bpp=16/g' /etc/xrdp/xrdp.ini && \
    sed -i 's/crypt_level=high/crypt_level=low/g' /etc/xrdp/xrdp.ini

# Set default session for XFCE
RUN echo "xfce4-session" > /home/runner/.xsession && \
    chown runner:runner /home/runner/.xsession

# XRDP runtime directory
RUN mkdir -p /var/run/xrdp && chmod 755 /var/run/xrdp

# Copy entrypoint script and remove Windows CRLF line endings
COPY entrypoint.sh /entrypoint.sh
RUN sed -i -e 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]