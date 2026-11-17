# TurtleBot4 Zenoh Setup Guide (Laptop + Multiple Robots)

This document is a full end-to-end runbook in English.
It covers setup from scratch on Laptop (Ubuntu 24.04 + ROS 2 Jazzy), first Wi-Fi connection on fresh robots, automated deployment, daily operation, and troubleshooting.

## Project Structure

Use this repository layout:

```text
turtlebot4_zenoh_setup/
├── laptop/
│   ├── cyclonedds_laptop.xml
│   ├── zenoh_both.json5
│   └── env.sh
└── turtlebot4/
    ├── cyclonedds_rpi.xml
    ├── zenoh_rpi.json5
    ├── setup.bash
    ├── zenoh-bridge.service
    ├── setup_network.sh
    └── deploy_robot.sh
```

What each file is for:
- laptop/cyclonedds_laptop.xml: lock laptop CycloneDDS to loopback (lo)
- laptop/zenoh_both.json5: laptop zenoh peer config with robot endpoints
- laptop/env.sh: laptop ROS and Zenoh runtime env, includes alias tb
- turtlebot4/cyclonedds_rpi.xml: lock robot CycloneDDS to usb0 (Create 3 link)
- turtlebot4/zenoh_rpi.json5: robot zenoh router config on port 7447
- turtlebot4/setup.bash: robot ROS environment exports
- turtlebot4/zenoh-bridge.service: systemd service for zenoh-bridge-ros2dds
- turtlebot4/setup_network.sh: robot network setup helper
- turtlebot4/deploy_robot.sh: laptop-side automated deploy script

## Phase 1: Laptop Installation and Configuration (From Zero)

Perform all steps below on Laptop (Ubuntu 24.04 + ROS 2 Jazzy).

### Step 1: Install CycloneDDS and required ROS 2 tools

```bash
sudo apt update
sudo apt install -y \
  ros-jazzy-rmw-cyclonedds-cpp \
  ros-jazzy-teleop-twist-keyboard \
  ros-jazzy-rviz2 \
  git curl
```

### Step 2: Install zenoh-bridge-ros2dds on Laptop and prepare package for Robot

1. Download release artifacts from the official Eclipse Zenoh ROS2DDS release page (version 1.9.0):
- Laptop package (Intel/AMD): zenoh-bridge-ros2dds_1.9.0_amd64.deb
- Robot package (Raspberry Pi ARM64): zenoh-bridge-ros2dds_1.9.0_arm64.deb

2. Install amd64 on Laptop and keep arm64 in home directory for deployment scripts:

```bash
sudo dpkg -i ~/Downloads/zenoh-bridge-ros2dds_1.9.0_amd64.deb || sudo apt-get install -f -y
cp ~/Downloads/zenoh-bridge-ros2dds_1.9.0_arm64.deb ~/zenoh-bridge-ros2dds_1.9.0_arm64.deb
zenoh-bridge-ros2dds --version
```

### Step 3: Clone the project and set executable permissions

You can use your own workspace path. Example:

```bash
mkdir -p ~/Documents/ROS/Projects
cd ~/Documents/ROS/Projects

git clone <YOUR_REPO_URL> turtlebot4_zenoh_setup
cd turtlebot4_zenoh_setup

chmod +x turtlebot4/deploy_robot.sh turtlebot4/setup_network.sh
```

### Step 4: Load laptop environment and tb alias from bashrc

```bash
cp ~/.bashrc ~/.bashrc.bak

grep -q "/opt/ros/jazzy/setup.bash" ~/.bashrc || echo "source /opt/ros/jazzy/setup.bash" >> ~/.bashrc
grep -q "turtlebot4_zenoh_setup/laptop/env.sh" ~/.bashrc || echo 'source "'$PWD'/laptop/env.sh"' >> ~/.bashrc

source ~/.bashrc
```

Quick check:

```bash
echo "$CYCLONEDDS_URI"
```

If the output points to laptop/cyclonedds_laptop.xml, laptop foundation is ready.

## Phase 2: Initial Wi-Fi Connection on Fresh Robot (Raspberry Pi)

If robot is new/offline, connect robot to the same Wi-Fi network as Laptop first.

### Step 1: Access Raspberry Pi terminal

Option A (Direct access):
- Connect HDMI display and USB keyboard to Raspberry Pi
- Login credentials (default):
  - User: ubuntu
  - Password: turtlebot4

Option B (Default robot hotspot):
- Connect Laptop to robot hotspot (usually Turtlebot4, password turtlebot4)
- SSH into Pi:

```bash
ssh ubuntu@192.168.185.3
```

### Step 2: Connect Pi to Lab/Office Wi-Fi and get IP address

On robot terminal:

```bash
sudo nmcli dev wifi connect "<WIFI_SSID>" password "<WIFI_PASSWORD>"
ip -4 -br addr show wlan0
```

Record robot IP (example: 10.11.57.174 and 10.11.57.175).

### Step 3: Verify internal Create 3 link

On robot terminal:

```bash
ping -c 3 192.168.186.2
```

Expected: successful replies from 192.168.186.2.

## Phase 3: Automated Deployment from Laptop to Each Robot

Return to Laptop terminal (same Wi-Fi network as robots).

### Step 1: Run deploy_robot.sh per robot

```bash
cd ~/Documents/ROS/Projects/turtlebot4_zenoh_setup

# Deploy for Robot 4 namespace
./turtlebot4/deploy_robot.sh <IP_ROBOT4> /robot4

# Deploy for Robot 5 namespace
./turtlebot4/deploy_robot.sh <IP_ROBOT5> /robot5
```

If prompted for SSH password, enter robot password (default: turtlebot4 unless changed).

What deploy script does on each robot:
1. Uploads robot-side config files
2. Installs ~/zenoh-bridge-ros2dds_1.9.0_arm64.deb if zenoh bridge is missing
3. Installs /etc/turtlebot4/cyclonedds_rpi.xml (DDS pinned to usb0)
4. Installs /etc/turtlebot4/setup.bash with selected namespace
5. Installs /etc/turtlebot4/zenoh_rpi.json5 (router mode on port 7447)
6. Installs /etc/systemd/system/zenoh-bridge.service
7. Installs /usr/local/sbin/tb4_setup_network.sh
8. Reloads systemd, restarts turtlebot4.service, enables zenoh-bridge.service
9. Verifies service status and port 7447 listening

### Step 2: Update robot IPs in laptop zenoh config

Edit:

```bash
nano laptop/zenoh_both.json5
```

Ensure endpoints match real robot IPs:

```json5
{
  mode: "peer",
  listen: {
    endpoints: ["tcp/127.0.0.1:0"]
  },
  connect: {
    endpoints: [
      "tcp/10.11.57.174:7447",
      "tcp/10.11.57.175:7447"
    ]
  },
  scouting: {
    multicast: {
      enabled: false
    }
  },
  plugins: {
    ros2dds: {
      domain: 0
    }
  }
}
```

## Phase 4: Daily Operation and Validation

### Step 1: Power robots and wait for full hardware readiness

- Power on one or both TurtleBot4 robots
- Wait about 45 to 60 seconds
- Confirm Create 3 is fully up (expected full LED readiness on base)

### Step 2: Start bridge on Laptop (Terminal 1)

```bash
tb
```

Keep this terminal running.

### Step 3: Validate data, teleop, and RViz (Terminal 2)

1. List topics:

```bash
ros2 daemon stop
ros2 topic list
```

Expected: namespaced topics for active robots, for example /robot4/... and /robot5/...

2. Check wheel status rate:

```bash
ros2 topic hz /robot4/wheel_status
ros2 topic hz /robot5/wheel_status
```

Expected: stable non-zero frequency (often around ~31 Hz depending on setup).

3. Teleop each robot:

```bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/robot4/cmd_vel
ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/robot5/cmd_vel
```

4. RViz per robot with tf remap:

```bash
rviz2 --ros-args -r /tf:=/robot4/tf -r /tf_static:=/robot4/tf_static
rviz2 --ros-args -r /tf:=/robot5/tf -r /tf_static:=/robot5/tf_static
```

## Phase 5: Quick Troubleshooting

### Case 1: tb runs but no robot topics on Laptop

1. Check robot hardware is fully initialized
2. Verify robot current IP address
3. Update laptop/zenoh_both.json5 with latest IPs
4. Restart tb command on Laptop
5. On robot, verify services:

```bash
systemctl is-active turtlebot4.service
systemctl is-active zenoh-bridge.service
ss -tlnp | grep 7447
```

### Case 2: tb command not found or wrong ROS network behavior

```bash
source ~/.bashrc
echo "$RMW_IMPLEMENTATION"
echo "$CYCLONEDDS_URI"
alias tb
```

Expected:
- RMW implementation is rmw_cyclonedds_cpp
- CYCLONEDDS_URI points to laptop/cyclonedds_laptop.xml
- alias tb exists

### Case 3: Change robot to another Wi-Fi later

On robot:

```bash
sudo /usr/local/sbin/tb4_setup_network.sh "<NEW_WIFI_SSID>" "<NEW_WIFI_PASSWORD>" "<NEW_IP_CIDR>" "<NEW_GATEWAY>"
```

Then update laptop/zenoh_both.json5 with new robot IP if needed.

## Important Notes

- This repository keeps one shared robot-side config set and deploys namespace per robot run
- Keep the arm64 package in home directory on Laptop for automatic robot installation
- Deb artifacts are ignored by .gitignore and should not be committed
