#!/usr/bin/env bash
set -e

# -- Parameters ---
# ROS2_GPG_KEY can be used to manually set a ros2 GPG key (optional)
# USE_CORE_COUNT is how many cores to use to operate the compilation (optional)
# USE_ROS2_BRANCH sets what apt repository branch to use (optional)
# PACKAGES is a Bash array of packages to get from apt (optional)

function getGPGKey {
    if [[ -z "${ROS2_GPG_KEY}" ]]; then
        echo "$(curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key)"
    else
        echo "${ROS2_GPG_KEY}"
    fi 
}

function getPackagesList {
    if [[ -z "${PACKAGES}" ]]; then
        echo "${PACKAGES}"
    else
        echo "$(curl -sSL https://raw.githubusercontent.com/harrywyatt5/InstallLabPrerequisites/refs/heads/main/packages.txt)"
    fi
}

if [[ "$(whoami)" != 'root' ]]; then
    echo 'You must run this script as root' >&2
    exit 1
fi

if [[ "${-}" != *i* ]]; then
    echo 'You must run this script in an interactive shell session' >&2
    exit 1
fi

source /etc/os-release
if [[ "${UBUNTU_CODENAME}" != 'jammy' ]]; then
    read -p 'WARN: This script was only designed for Ubuntu 22.04, so may not work. Press ENTER to continue...'
fi

# Install virt-what to check if we are running on a hypervisor and curl to download the required dependency list
add-apt-repository universe
apt update
apt install virt-what curl -y

if ! virt-what; then
    read -p 'WARN: This system is not a virtual machine. It is highly recommended to run this script in a VM. Press ENTER to continue...'
fi

# Install ros2
getGPGKey > /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} ${USE_ROS2_BRANCH}" >> /etc/apt/sources.list.d/ros2.list
apt update
apt install ros-humble-desktop-full -y
source /opt/ros/humble/setup.bash

# Install additional packages
getPackagesList | xargs apt install -y
