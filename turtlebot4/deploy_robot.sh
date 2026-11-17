#!/usr/bin/env bash
set -euo pipefail

# USER INPUT:
#   Arg 1 = Robot IP address on your Wi-Fi LAN
#   Arg 2 = Robot namespace (optional), e.g. /robot, /robot4, /robot5
# Example:
#   ./deploy_robot.sh 10.11.57.175 /robot5
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <IP_ROBOT> [ROBOT_NAMESPACE]"
  echo "Example: $0 10.11.57.175 /robot5"
  exit 1
fi

ROBOT_IP="$1"
ROBOT_NAMESPACE="${2:-/robot}"
REMOTE_USER="ubuntu"
REMOTE_HOST="${REMOTE_USER}@${ROBOT_IP}"
DEB_PATH="$HOME/zenoh-bridge-ros2dds_1.9.0_arm64.deb"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_LOCAL_DIR="$(mktemp -d)"
TMP_REMOTE_DIR="/tmp/tb4_zenoh_setup"

cleanup() {
  rm -rf "$TMP_LOCAL_DIR"
}
trap cleanup EXIT

echo "[INFO] Preparing temporary deployment files"
cp "$SCRIPT_DIR/cyclonedds_rpi.xml" "$TMP_LOCAL_DIR/cyclonedds_rpi.xml"
cp "$SCRIPT_DIR/zenoh-bridge.service" "$TMP_LOCAL_DIR/zenoh-bridge.service"
cp "$SCRIPT_DIR/setup_network.sh" "$TMP_LOCAL_DIR/setup_network.sh"
cp "$SCRIPT_DIR/zenoh_rpi.json5" "$TMP_LOCAL_DIR/zenoh_rpi.json5"

sed "s|^export ROBOT_NAMESPACE=.*$|export ROBOT_NAMESPACE=\"${ROBOT_NAMESPACE}\"|" \
  "$SCRIPT_DIR/setup.bash" > "$TMP_LOCAL_DIR/setup.bash"

echo "[INFO] Copying files to ${REMOTE_HOST}"
ssh -o StrictHostKeyChecking=accept-new "$REMOTE_HOST" "mkdir -p $TMP_REMOTE_DIR"
scp "$TMP_LOCAL_DIR/cyclonedds_rpi.xml" "$REMOTE_HOST:$TMP_REMOTE_DIR/"
scp "$TMP_LOCAL_DIR/zenoh-bridge.service" "$REMOTE_HOST:$TMP_REMOTE_DIR/"
scp "$TMP_LOCAL_DIR/setup_network.sh" "$REMOTE_HOST:$TMP_REMOTE_DIR/"
scp "$TMP_LOCAL_DIR/setup.bash" "$REMOTE_HOST:$TMP_REMOTE_DIR/"
scp "$TMP_LOCAL_DIR/zenoh_rpi.json5" "$REMOTE_HOST:$TMP_REMOTE_DIR/"

if [[ -f "$DEB_PATH" ]]; then
  echo "[INFO] Found local Zenoh deb. Uploading package"
  scp "$DEB_PATH" "$REMOTE_HOST:~/"
else
  echo "[WARN] Deb package not found at $DEB_PATH"
fi

echo "[INFO] Running remote install and service setup"
ssh "$REMOTE_HOST" "ROBOT_NAMESPACE='$ROBOT_NAMESPACE' TMP_REMOTE_DIR='$TMP_REMOTE_DIR' DEB_FILE='$(basename "$DEB_PATH")' bash -s" <<'EOF'
set -euo pipefail

if ! command -v zenoh-bridge-ros2dds >/dev/null 2>&1; then
  if [[ -f "$HOME/$DEB_FILE" ]]; then
    echo "[INFO] Installing zenoh-bridge-ros2dds from deb"
    sudo dpkg -i "$HOME/$DEB_FILE" || sudo apt-get install -f -y
  else
    echo "[ERROR] zenoh-bridge-ros2dds is missing and deb package was not uploaded"
    exit 1
  fi
fi

sudo install -m 644 -o root -g root "$TMP_REMOTE_DIR/cyclonedds_rpi.xml" /etc/turtlebot4/cyclonedds_rpi.xml
sudo install -m 644 -o root -g root "$TMP_REMOTE_DIR/zenoh_rpi.json5" /etc/turtlebot4/zenoh_rpi.json5
sudo install -m 644 -o root -g root "$TMP_REMOTE_DIR/setup.bash" /etc/turtlebot4/setup.bash
sudo install -m 755 -o root -g root "$TMP_REMOTE_DIR/setup_network.sh" /usr/local/sbin/tb4_setup_network.sh
sudo install -m 644 -o root -g root "$TMP_REMOTE_DIR/zenoh-bridge.service" /etc/systemd/system/zenoh-bridge.service

sudo systemctl daemon-reload
sudo systemctl restart turtlebot4.service
sleep 5
sudo systemctl enable --now zenoh-bridge.service

echo "[INFO] Service states"
systemctl is-active turtlebot4.service
systemctl is-active zenoh-bridge.service

echo "[INFO] Listening ports"
sudo ss -tlnp | grep 7447 || true

echo "[INFO] Quick topic check"
if [[ -f /opt/ros/jazzy/setup.bash ]]; then
  source /opt/ros/jazzy/setup.bash
fi
if [[ -f /etc/turtlebot4/setup.bash ]]; then
  source /etc/turtlebot4/setup.bash
fi
timeout 5 ros2 topic hz "${ROBOT_NAMESPACE}/wheel_status" || true

echo "[DONE] Robot deploy complete"
EOF

echo "[DONE] Deployment complete for $REMOTE_HOST"
echo "[NOTE] If robot IP changed, update laptop/zenoh_both.json5 endpoints"