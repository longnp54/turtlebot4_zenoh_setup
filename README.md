# TurtleBot4 Zenoh Setup

Project nay toi uu cho mo hinh Laptop + TurtleBot4 voi cau hinh Zenoh gon nhe:
- Laptop chi dung 1 lenh `tb`
- Robot dung 1 bo cau hinh chung, khong tach robot4/robot5

## Cau truc thu muc

```
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

## Luong mang

- Create 3 <-> usb0 <-> RPi CycloneDDS
- RPi Zenoh Router lang nghe `tcp/0.0.0.0:7447`
- Laptop Zenoh Peer ket noi den robot IP trong `laptop/zenoh_both.json5`
- Laptop CycloneDDS chi chay tren `lo`

## Quy trinh setup robot moi/trang

1. Dang nhap vao Raspberry Pi cua robot.
2. Chay script setup mang tren robot:

```bash
chmod +x /tmp/setup_network.sh
/tmp/setup_network.sh "<WIFI_SSID>" "<WIFI_PASSWORD>"
```

Neu ban da copy script vao robot qua deploy thi co the chay:

```bash
sudo /usr/local/sbin/tb4_setup_network.sh "<WIFI_SSID>" "<WIFI_PASSWORD>"
```

Script se:
- ket noi Wi-Fi qua nmcli (neu co SSID/PASS)
- kiem tra usb0 va ping den Create 3
- mo cong 7447 neu ufw dang bat
- locale-gen en_US.UTF-8
- in IP hien tai cua wlan0

3. Tu laptop, day cau hinh sang robot:

```bash
cd /home/longnp54/Documents/ROS/Projects/turtlebot4_zenoh_setup
chmod +x turtlebot4/deploy_robot.sh turtlebot4/setup_network.sh
./turtlebot4/deploy_robot.sh <IP_ROBOT> [/robot_namespace]
```

Vi du:

```bash
./turtlebot4/deploy_robot.sh 10.11.57.175 /robot5
```

Neu ton tai file `~/zenoh-bridge-ros2dds_1.9.0_arm64.deb`, script se tu dong copy va cai dat khi robot chua co `zenoh-bridge-ros2dds`.

## Van hanh hang ngay tren Laptop

Mo terminal moi, go:

```bash
tb
```

Sau do o terminal khac:

```bash
ros2 topic list
ros2 run teleop_twist_keyboard teleop_twist_keyboard
rviz2
```

Neu can remap `/tf` trong RViz hoac node rieng, dung remap tuy theo launch cua ban.

## Ghi chu

- Neu IP robot thay doi, cap nhat endpoint trong `laptop/zenoh_both.json5`.
- File `.deb` duoc bo qua boi `.gitignore`, khong dua vao Git.