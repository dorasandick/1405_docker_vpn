#!/bin/bash
set -e

# Default environment variables
ENABLE_VPN=${ENABLE_VPN:-"true"}
ENABLE_RDP=${ENABLE_RDP:-"false"}
RDP_PASSWORD=${RDP_PASSWORD:-"SecretPass123!"}
HOSTNAME=${HOSTNAME:-"docker-vpn-runner"}

# 1. Configure RDP user password
echo "runner:$RDP_PASSWORD" | chpasswd

# 2. Setup TUN device if missing
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

# 3. Apply Networking/Firewall rules for Exit Node mode
if [ "$ENABLE_VPN" = "true" ]; then
    echo "[-] Configuring IP Forwarding and NAT Masquerade..."
    DEFAULT_IFACE=$(ip route show default | awk '{print $5}' | head -n1)

    iptables -t nat -A POSTROUTING -o "$DEFAULT_IFACE" -j MASQUERADE || true
    iptables -A FORWARD -i tailscale0 -j ACCEPT || true
    iptables -A FORWARD -o tailscale0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true
fi

# 4. Start Tailscale Daemon in background
echo "[-] Starting tailscaled..."
tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
sleep 2

# 5. Authenticate and connect Tailscale
if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    TS_FLAGS="--authkey=${TAILSCALE_AUTH_KEY} --ssh --hostname=${HOSTNAME} --accept-routes"
    if [ "$ENABLE_VPN" = "true" ]; then
        TS_FLAGS="$TS_FLAGS --advertise-exit-node"
    fi
    echo "[-] Authenticating with Tailscale..."
    tailscale up $TS_FLAGS
else
    echo "[!] WARNING: TAILSCALE_AUTH_KEY not provided. Connect manually via docker exec."
fi

# 6. Start XRDP services if RDP mode is enabled
if [ "$ENABLE_RDP" = "true" ]; then
    echo "[-] Starting XRDP services..."
    /etc/init.d/xrdp start
fi

# 7. Output Connection Details
TS_IP=$(tailscale ip -4 2>/dev/null || echo "Pending")
echo "================================================="
echo " RUNNER IS ONLINE AND READY"
echo "================================================="
echo "Tailscale IP:      $TS_IP"
echo "SSH Access:        tailscale ssh runner@${HOSTNAME}"
echo "VPN Exit Node:     $ENABLE_VPN"
echo "RDP Enabled:       $ENABLE_RDP"
if [ "$ENABLE_RDP" = "true" ]; then
  echo "RDP Host:          $TS_IP:3389"
  echo "RDP User:          runner"
fi
echo "================================================="

# Trap shutdown signals to cleanly log out from the Tailnet
cleanup() {
    echo "[-] Stopping container & logging out of Tailscale..."
    tailscale logout || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# Keep container alive
tail -f /dev/null &
wait $!