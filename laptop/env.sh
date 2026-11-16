export TB4_ZENOH_PROJECT_DIR="/home/longnp54/Documents/ROS/Projects/turtlebot4_zenoh_setup"

export ROS_DOMAIN_ID=0
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI="file://$TB4_ZENOH_PROJECT_DIR/laptop/cyclonedds_laptop.xml"
unset ROS_AUTOMATIC_DISCOVERY_RANGE

alias tb="zenoh-bridge-ros2dds -c $TB4_ZENOH_PROJECT_DIR/laptop/zenoh_both.json5"
