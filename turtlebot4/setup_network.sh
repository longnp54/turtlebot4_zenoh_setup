#!/usr/bin/env bash
set -euo pipefail

# USER INPUT (optional):
#   Arg 1 = Wi-Fi SSID name
#   Arg 2 = Wi-Fi password (leave empty for open network)
#   Arg 3 = Static IPv4 in CIDR format for wlan0
#   Arg 4 = Default gateway
# Example:
#   ./setup_network.sh "Office-WiFi" "my_password" "10.11.57.175/20" "10.11.48.1"
SSID="${1:-UET-Wifi-Office-Free 5Ghz}"
PASS="${2:-}"
WLAN_IP="${3:-10.11.57.175/20}"
WLAN_GW="${4:-10.11.48.1}"

echo "[INFO] Starting network setup on Raspberry Pi"

echo "[INFO] Writing /etc/netplan/50-wifis.yaml for SSID: $SSID"
if [[ -n "$PASS" ]]; then
  sudo bash -c "cat > /etc/netplan/50-wifis.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
  wifis:
    wlan0:
      dhcp4: false
      optional: true
      addresses:
        - $WLAN_IP
      routes:
        - to: default
          via: $WLAN_GW
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      access-points:
        \"$SSID\":
          password: \"$PASS\"
EOF"
else
  sudo bash -c "cat > /etc/netplan/50-wifis.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
  wifis:
    wlan0:
      dhcp4: false
      optional: true
      addresses:
        - $WLAN_IP
      routes:
        - to: default
          via: $WLAN_GW
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      access-points:
        \"$SSID\": {}
EOF"
fi

echo "[INFO] Securing netplan yaml permissions"
sudo chown root:root /etc/netplan/*.yaml
sudo chmod 600 /etc/netplan/*.yaml

echo "[INFO] Applying netplan"
sudo netplan apply

echo "[INFO] Checking usb0 address"
if ip -4 -br addr show usb0 | grep -q "192.168.186.3"; then
  echo "[OK] usb0 has 192.168.186.3"
else
  echo "[WARN] usb0 does not have 192.168.186.3"
  ip -4 -br addr show usb0 || true
fi

echo "[INFO] Pinging Create 3 at 192.168.186.2"
if ping -I usb0 -c 2 192.168.186.2; then
  echo "[OK] Create 3 reachable over usb0"
else
  echo "[WARN] Cannot reach Create 3 at 192.168.186.2"
fi

if sudo ufw status | grep -q active; then
  echo "[INFO] UFW is active. Allowing tcp/7447"
  sudo ufw allow 7447/tcp
else
  echo "[INFO] UFW is not active"
fi

echo "[INFO] Generating locale en_US.UTF-8"
sudo locale-gen en_US.UTF-8 || true

echo "[INFO] Current wlan0 IPv4"
ip -4 -br addr show wlan0 || true

echo "[DONE] setup_network.sh completed"