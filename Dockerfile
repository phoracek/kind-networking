FROM docker.io/kindest/node:v1.17.0

RUN \
    apt-get update && \
    apt-get -y install systemd network-manager && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN \
    echo '[keyfile]\nunmanaged-devices=interface-name:veth*' > /etc/NetworkManager/conf.d/10-globally-managed-devices.conf && \
    systemctl enable network-manager
