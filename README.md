# TurtleBot4 Multi-Robot Zenoh Setup Guide

End-to-end setup and operation guide for controlling one or multiple **TurtleBot 4** robots from a single **Laptop (Ubuntu 24.04 + ROS 2 Jazzy)** over Wi-Fi using **Eclipse Zenoh** (`zenoh-bridge-ros2dds`).

## Architecture Overview

To prevent DDS multicast storms over Wi-Fi and isolate robot namespaces, DDS traffic is split into two isolated domains bridged by Zenoh over TCP:

```text
[Laptop: ROS 2 Jazzy] ──(CycloneDDS on lo)──> [Zenoh Peer]
                                                   │
                                          Wi-Fi (TCP :7447)
                                                   │
[Create 3 Base] <──(CycloneDDS on usb0)── [RPi: Zenoh Router]
```

## Customization Placeholders (Read Before Starting)

Throughout this guide, replace `<PLACEHOLDER>` values with your own setup parameters:

| Placeholder | Required? | Description & Example |
| :--- | :--- | :--- |
| `<WORKSPACE_DIR>` | Optional | Any folder on your Laptop to store this repo (e.g., `~/ros2_ws` or `~/projects`). |
| `<ROBOT_IP>` | **Required** | IPv4 address of the TurtleBot 4 on your Wi-Fi network (e.g., `192.168.1.101`). |
| `<ROBOT_NAMESPACE>` | Optional | Unique ROS 2 namespace per robot to avoid topic collisions (e.g., `/robot1`, `/tb4_a`). Required when running multiple robots. |
| `<WIFI_SSID>` | **Required** | Name of your lab/office Wi-Fi network (e.g., `"My_Lab_WiFi"`). |
| `<WIFI_PASSWORD>` | Optional | Wi-Fi password. Pass `""` if connecting to an open/passwordless network. |
| `<STATIC_IP/CIDR>` | Optional | Desired static IP + subnet mask for the robot (e.g., `192.168.1.101/24`). |
| `<GATEWAY>` | Optional | Default router gateway IP for your Wi-Fi network (e.g., `192.168.1.1`). |

## Repository Structure

```text
turtlebot4_zenoh_setup/
├── laptop/
│   ├── cyclonedds_laptop.xml   # Locks Laptop CycloneDDS to loopback (lo)
│   ├── zenoh_both.json5        # Laptop Zenoh peer config with robot IP endpoints
│   └── env.sh                  # Laptop ROS/Zenoh environment variables & 'tb' alias
└── turtlebot4/
    ├── cyclonedds_rpi.xml      # Locks Robot CycloneDDS to Create 3 USB link (usb0)
    ├── zenoh_rpi.json5         # Robot Zenoh router config (listens on port 7447)
    ├── setup.bash              # Robot ROS 2 environment and namespace exports
    ├── zenoh-bridge.service    # Systemd service for auto-starting Zenoh on boot
    ├── setup_network.sh        # Helper script to configure Static Wi-Fi & port 7447
    └── deploy_robot.sh         # Automated deployment script run from Laptop
```

---

## Phase 1: Laptop Setup (Ubuntu 24.04 + ROS 2 Jazzy)

Perform all steps below on your **Laptop**.

### 1. Install ROS 2 Dependencies

```bash
sudo apt update
sudo apt install -y \
  ros-jazzy-rmw-cyclonedds-cpp \
  ros-jazzy-teleop-twist-keyboard \
  ros-jazzy-rviz2 \
  git curl
```

### 2. Install `zenoh-bridge-ros2dds` (v1.9.0)

1. Download both `.deb` packages from the [Eclipse Zenoh ROS2DDS Releases](https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds/releases) page into `~/Downloads`:
   - **Laptop (Intel/AMD):** `zenoh-bridge-ros2dds_1.9.0_amd64.deb`
   - **Robot (Raspberry Pi ARM64):** `zenoh-bridge-ros2dds_1.9.0_arm64.deb`

2. Install the `amd64` package on your Laptop and stage the `arm64` package in your home directory (`~/`) for automated robot deployment:

```bash
sudo dpkg -i ~/Downloads/zenoh-bridge-ros2dds_1.9.0_amd64.deb || sudo apt-get install -f -y
cp ~/Downloads/zenoh-bridge-ros2dds_1.9.0_arm64.deb ~/

# Verify installation
zenoh-bridge-ros2dds --version
```

### 3. Clone Repository & Configure Shell Environment

```bash
# Replace <WORKSPACE_DIR> with your preferred folder (Example: ~/ros2_ws)
mkdir -p <WORKSPACE_DIR>
cd <WORKSPACE_DIR>

git clone [https://github.com/longnp54/turtlebot4_zenoh_setup.git](https://github.com/longnp54/turtlebot4_zenoh_setup.git)
cd turtlebot4_zenoh_setup

chmod +x turtlebot4/deploy_robot.sh turtlebot4/setup_network.sh
```

Add ROS 2 and Laptop Zenoh environment variables to `~/.bashrc`:

```bash
cp ~/.bashrc ~/.bashrc.bak

grep -q "/opt/ros/jazzy/setup.bash" ~/.bashrc || echo "source /opt/ros/jazzy/setup.bash" >> ~/.bashrc
grep -q "turtlebot4_zenoh_setup/laptop/env.sh" ~/.bashrc || echo "source $PWD/laptop/env.sh" >> ~/.bashrc

source ~/.bashrc
```

Verify that `CYCLONEDDS_URI` points to `laptop/cyclonedds_laptop.xml`:

```bash
echo "$CYCLONEDDS_URI"
```

---

## Phase 2: TurtleBot 4 Network Setup (Wi-Fi, Static IP & Port 7447)

Perform these steps on **each TurtleBot 4 (Raspberry Pi)** so it is reachable on the same Wi-Fi network as your Laptop and allows Zenoh traffic on TCP port `7447`.

### 1. Access the Raspberry Pi Terminal

- **Option A (Direct):** Connect an HDMI monitor and USB keyboard to the Raspberry Pi.
- **Option B (AP Hotspot):** Connect your Laptop to the robot's default hotspot (`Turtlebot4`) and SSH in:
  ```bash
  ssh ubuntu@192.168.185.3
  ```
*(Default credentials — User: `ubuntu` | Password: `turtlebot4`)*

### 2. Connect Robot to Wi-Fi

Choose **either** a quick DHCP connection or a Static IP setup:

- **Option 2A — Quick DHCP Connection (Dynamic IP):**
  ```bash
  sudo nmcli dev wifi connect "<WIFI_SSID>" password "<WIFI_PASSWORD>"
  ip -4 -br addr show wlan0
  ```

- **Option 2B — Static IP + Firewall Setup (Recommended for Multi-Robot):**  
  Transfer `turtlebot4/setup_network.sh` to the robot (or use `/usr/local/sbin/tb4_setup_network.sh` after Phase 3) and run:
  ```bash
  chmod +x setup_network.sh

  # Syntax: ./setup_network.sh "<WIFI_SSID>" "<WIFI_PASSWORD>" "<STATIC_IP/CIDR>" "<GATEWAY>"
  # Example (Wi-Fi with password):
  ./setup_network.sh "My_Lab_WiFi" "secret123" "192.168.1.101/24" "192.168.1.1"

  # Example (Open Wi-Fi without password):
  ./setup_network.sh "My_Open_WiFi" "" "192.168.1.101/24" "192.168.1.1"
  ```

### 3. Verify Create 3 USB Connection

Confirm that the Raspberry Pi (`192.168.186.3`) can communicate with the Create 3 base (`192.168.186.2`) over `usb0`:

```bash
ping -c 3 192.168.186.2
```

---

## Phase 3: TurtleBot 4 Zenoh & CycloneDDS Setup

Install and configure `zenoh-bridge-ros2dds` (router mode on port `7447`) and CycloneDDS (`usb0` isolation) on **each TurtleBot 4**. Choose **Option A** (recommended) or **Option B**.

### Option A: Automated Deployment from Laptop (Recommended)

From your **Laptop terminal** (on the same Wi-Fi network as the robots), run `deploy_robot.sh` once per robot with its IP and unique namespace:

```bash
cd <WORKSPACE_DIR>/turtlebot4_zenoh_setup

# Syntax: ./turtlebot4/deploy_robot.sh <ROBOT_IP> <ROBOT_NAMESPACE>
# Example for multiple robots:
./turtlebot4/deploy_robot.sh 192.168.1.101 /robot1
./turtlebot4/deploy_robot.sh 192.168.1.102 /robot2
```

*(Enter the robot's SSH password when prompted — default is `turtlebot4`.)*

**What `deploy_robot.sh` automates on each robot:**
1. Copies and installs `~/zenoh-bridge-ros2dds_1.9.0_arm64.deb` on the Raspberry Pi.
2. Installs `/etc/turtlebot4/cyclonedds_rpi.xml` (pins CycloneDDS strictly to `usb0`).
3. Installs `/etc/turtlebot4/setup.bash` with your chosen `<ROBOT_NAMESPACE>`.
4. Installs `/etc/turtlebot4/zenoh_rpi.json5` (Zenoh router listening on `tcp/0.0.0.0:7447`).
5. Installs `/usr/local/sbin/tb4_setup_network.sh` for future network updates.
6. Enables and starts `/etc/systemd/system/zenoh-bridge.service`, then restarts `turtlebot4.service`.

### Option B: Manual Setup Directly on TurtleBot 4 (Raspberry Pi)

If you prefer to configure the robot directly on the Raspberry Pi without `deploy_robot.sh`:

1. **Copy `zenoh-bridge-ros2dds_1.9.0_arm64.deb` and the `turtlebot4/` directory** onto the Raspberry Pi (e.g., into `~/turtlebot4/`).
2. **Install the Zenoh bridge package:**
   ```bash
   sudo dpkg -i ~/zenoh-bridge-ros2dds_1.9.0_arm64.deb || sudo apt-get install -f -y
   zenoh-bridge-ros2dds --version
   ```
3. **Install configuration files & set `<ROBOT_NAMESPACE>`** (replace `/robot1` with your desired namespace):
   ```bash
   sudo mkdir -p /etc/turtlebot4
   sudo cp ~/turtlebot4/cyclonedds_rpi.xml /etc/turtlebot4/cyclonedds_rpi.xml
   sudo cp ~/turtlebot4/zenoh_rpi.json5 /etc/turtlebot4/zenoh_rpi.json5
   sudo cp ~/turtlebot4/setup.bash /etc/turtlebot4/setup.bash

   # Replace <ROBOT_NAMESPACE> (Example: /robot1)
   sudo sed -i 's|ROBOT_NAMESPACE=.*|ROBOT_NAMESPACE="<ROBOT_NAMESPACE>"|g' /etc/turtlebot4/setup.bash
   ```
4. **Enable and start the Zenoh systemd service:**
   ```bash
   sudo cp ~/turtlebot4/zenoh-bridge.service /etc/systemd/system/zenoh-bridge.service
   sudo systemctl daemon-reload
   sudo systemctl enable --now zenoh-bridge.service
   sudo systemctl restart turtlebot4.service
   ```

### 1. Verify Zenoh on Each Robot

Check that `zenoh-bridge.service` is active and listening on TCP port `7447`:

```bash
systemctl is-active zenoh-bridge.service
ss -tlnp | grep 7447
```

### 2. Register Robot IPs on the Laptop

On your **Laptop**, edit `laptop/zenoh_both.json5` and add `"tcp/<ROBOT_IP>:7447"` under `connect.endpoints` for every robot you want to connect:

```bash
nano laptop/zenoh_both.json5
```

```json5
{
  mode: "peer",
  listen: {
    endpoints: ["tcp/127.0.0.1:0"]
  },
  connect: {
    endpoints: [
      "tcp/<ROBOT_1_IP>:7447", // Example: "tcp/192.168.1.101:7447"
      "tcp/<ROBOT_2_IP>:7447"  // Example: "tcp/192.168.1.102:7447"
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

---

## Phase 4: Daily Operation & Validation

### 1. Power On Robots
Turn on your robots and wait **45–60 seconds** until the Create 3 base chimes and its white LED ring turns solid.

### 2. Start the Zenoh Bridge on Laptop (Terminal 1)

```bash
tb
```

Keep this terminal running in the background while operating the robots.

### 3. Verify Topics & Control Robots (Terminal 2)

1. **List active robot topics:**
   ```bash
   ros2 daemon stop
   ros2 topic list
   ```
   Expected output includes topics prefixed with each active `<ROBOT_NAMESPACE>` (e.g., `/robot1/cmd_vel`, `/robot2/cmd_vel`).

2. **Check topic publish rate:**
   ```bash
   # Example: ros2 topic hz /robot1/wheel_status
   ros2 topic hz <ROBOT_NAMESPACE>/wheel_status
   ```

3. **Teleoperate a specific robot:**
   ```bash
   # Example: ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/robot1/cmd_vel
   ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=<ROBOT_NAMESPACE>/cmd_vel
   ```

4. **Visualize a specific robot in RViz2 (with TF remapping):**
   ```bash
   # Example: rviz2 --ros-args -r /tf:=/robot1/tf -r /tf_static:=/robot1/tf_static
   rviz2 --ros-args -r /tf:=<ROBOT_NAMESPACE>/tf -r /tf_static:=<ROBOT_NAMESPACE>/tf_static
   ```

---

## Phase 5: Troubleshooting & Network Updates

### 1. `tb` is running, but no robot topics appear on Laptop
- Confirm the robot has finished booting (45–60s) and verify its current IP (`ip -4 -br addr show wlan0`).
- Ensure the IP in `laptop/zenoh_both.json5` matches `<ROBOT_IP>`, then restart `tb`.
- SSH into the robot and verify services and port `7447`:
  ```bash
  systemctl is-active turtlebot4.service
  systemctl is-active zenoh-bridge.service
  ss -tlnp | grep 7447
  ```

### 2. `tb: command not found` or DDS cross-talk on Laptop
Reload `~/.bashrc` and verify environment variables:
```bash
source ~/.bashrc
echo "$RMW_IMPLEMENTATION"   # Expected: rmw_cyclonedds_cpp
echo "$CYCLONEDDS_URI"       # Expected: file:///.../laptop/cyclonedds_laptop.xml
alias tb
```

### 3. Switch Wi-Fi or Change Static IP Later
On the robot terminal, run the installed network helper script:

```bash
# Syntax: sudo /usr/local/sbin/tb4_setup_network.sh "<WIFI_SSID>" "<WIFI_PASSWORD>" "<STATIC_IP/CIDR>" "<GATEWAY>"
sudo /usr/local/sbin/tb4_setup_network.sh "<NEW_WIFI_SSID>" "<NEW_WIFI_PASSWORD>" "<NEW_STATIC_IP/CIDR>" "<NEW_GATEWAY>"
```

Then update `laptop/zenoh_both.json5` with the new `<ROBOT_IP>` and restart `tb` on your Laptop.