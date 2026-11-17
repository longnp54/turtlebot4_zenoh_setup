#!/usr/bin/env bash

# Tự động xác định đường dẫn tuyệt đối của project dựa trên vị trí file env.sh
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
  _SCRIPT_DIR="$(pwd)"
fi

export TB4_ZENOH_PROJECT_DIR="$(cd "$_SCRIPT_DIR/.." && pwd)"
unset _SCRIPT_DIR

# Cấu hình ROS 2 & CycloneDDS
export ROS_DOMAIN_ID=0
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI="file://$TB4_ZENOH_PROJECT_DIR/laptop/cyclonedds_laptop.xml"
unset ROS_AUTOMATIC_DISCOVERY_RANGE

# Alias khởi chạy nhanh Zenoh Bridge
alias tb="zenoh-bridge-ros2dds -c \"$TB4_ZENOH_PROJECT_DIR/laptop/zenoh_both.json5\""