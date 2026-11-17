#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script cấu hình mạng (Static Wi-Fi + USB Create 3 + Zenoh Port) cho TurtleBot 4
# ==============================================================================

SSID="${1:-}"
PASS="${2:-}"
WLAN_IP="${3:-}"
WLAN_GW="${4:-}"

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m   $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }

# 1. Kiểm tra tham số đầu vào
if [[ -z "$SSID" || -z "$WLAN_IP" || -z "$WLAN_GW" ]]; then
  echo "❌ Thiếu thông tin cấu hình mạng!"
  echo ""
  echo "Cách chạy:"
  echo "  ./setup_network.sh <TEN_WIFI> <MAT_KHAU> <IP_TINH_ROBOT/SUBNET> <GATEWAY>"
  echo ""
  echo "Ví dụ Wi-Fi có mật khẩu:"
  echo "  ./setup_network.sh \"Lab_WiFi\" \"12345678\" \"192.168.1.101/24\" \"192.168.1.1\""
  echo ""
  echo "Ví dụ Wi-Fi không mật khẩu (mạng mở):"
  echo "  ./setup_network.sh \"Free_WiFi\" \"\" \"10.11.57.175/20\" \"10.11.48.1\""
  exit 1
fi

# 2. Dọn các file netplan cũ (như 90-NM-*.yaml) cấu hình trùng wlan0 để tránh bị đè routes
sudo mkdir -p /etc/netplan/backup
for f in /etc/netplan/*.yaml; do
  if [[ -f "$f" && "$f" != "/etc/netplan/50-wifis.yaml" ]] && sudo grep -q "wlan0" "$f"; then
    info "Di chuyển file netplan cũ gây xung đột: $f -> /etc/netplan/backup/"
    sudo mv "$f" /etc/netplan/backup/
  fi
done

# 3. Tạo file cấu hình Netplan cho wlan0
info "Đang cấu hình Wi-Fi ($SSID) với IP tĩnh ($WLAN_IP), Gateway ($WLAN_GW)..."

if [[ -n "$PASS" ]]; then
  WIFI_AUTH="\"$SSID\":
          password: \"$PASS\""
else
  WIFI_AUTH="\"$SSID\": {}"
fi

sudo tee /etc/netplan/50-wifis.yaml > /dev/null <<EOF
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
        $WIFI_AUTH
EOF

# 4. Cấp đúng quyền root:root (600) và áp dụng cấu hình mạng
info "Áp dụng cấu hình Netplan..."
sudo chown root:root /etc/netplan/*.yaml
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan apply
sleep 2

# 5. Kiểm tra Default Route & Internet
if ip route show default | grep -q "via $WLAN_GW"; then
  ok "Default Gateway ($WLAN_GW) đã được thiết lập thành công"
  if ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
    ok "Kết nối Internet (8.8.8.8) thông suốt"
  else
    warn "Đã có Gateway nhưng không ping được 8.8.8.8 (Wi-Fi có thể chặn Internet với IP tĩnh, LAN/Zenoh vẫn chạy bình thường)"
  fi
else
  warn "Chưa tạo được Default Route! Hãy kiểm tra lại Subnet Mask của $WLAN_IP có cùng dải với Gateway $WLAN_GW không."
fi

# 6. Kiểm tra kết nối nội bộ với đế Create 3 qua cổng usb0
info "Kiểm tra kết nối USB với Create 3..."
if ip -4 -br addr show usb0 2>/dev/null | grep -q "192.168.186.3"; then
  ok "Cổng usb0 đã nhận IP 192.168.186.3"
else
  warn "Cổng usb0 chưa có IP 192.168.186.3 (kiểm tra lại cáp USB nối với Create 3)"
fi

if ping -I usb0 -c 2 -W 2 192.168.186.2 >/dev/null 2>&1; then
  ok "Ping tới Create 3 (192.168.186.2) thành công"
else
  warn "Không thể ping tới Create 3 (192.168.186.2)"
fi

# 7. Mở cổng Zenoh (7447/tcp) nếu bật tường lửa UFW & fix Locale
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "active"; then
  info "Mở cổng 7447/tcp trên UFW cho Zenoh..."
  sudo ufw allow 7447/tcp >/dev/null
  ok "Đã mở cổng 7447/tcp"
fi

sudo sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
sudo locale-gen en_US.UTF-8 >/dev/null 2>&1 || true

# 8. Hiển thị kết quả cuối cùng
echo "------------------------------------------------------------"
ok "Hoàn tất cài đặt mạng! Thông tin IP & Route hiện tại:"
ip -4 -br addr show wlan0 || true
ip route show default || true
echo "------------------------------------------------------------"