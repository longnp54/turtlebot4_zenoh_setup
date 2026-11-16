#!/usr/bin/env bash
set -euo pipefail

SSID="${1:-}"
PASS="${2:-}"

echo "[INFO] Starting network setup on Raspberry Pi"

if [[ -n "$SSID" && -n "$PASS" ]]; then
  if command -v nmcli >/dev/null 2>&1; then
    echo "[INFO] Connecting wlan0 to SSID: $SSID"
    if ! nmcli dev wifi connect "$SSID" password "$PASS" ifname wlan0; then
      echo "[WARN] nmcli could not connect wlan0. Check NetworkManager control or use netplan manually."
    fi
  else
    echo "[WARN] nmcli not found. Configure Wi-Fi manually (netplan/NetworkManager)."
  fi
fi

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