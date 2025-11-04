#!/usr/bin/env bash
set -e

# -- Parameters ---
# ROS2_GPG_KEY can be used to manually set a ros2 GPG key (optional)
# USE_CORE_COUNT is how many cores to use to operate the compilation (optional)
# USE_ROS2_BRANCH sets what apt repository branch to use (optional)
# PACKAGES is a newline-separated list of packages to get from apt (optional)
# GITHUB_SSH_KEY will use SSH rather than HTTPS to clone Git packages if set, offering that SSH key to GitHub (optional)
INSTALL_USER="$(logname)"
SDFORMAT9_BRANCH=''

function getGPGKey {
    if [[ -z "${ROS2_GPG_KEY}" ]]; then
        echo "$(curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key)"
    else
        echo "${ROS2_GPG_KEY}"
    fi 
}

function run_as_install_user {
    su - "${INSTALL_USER}" -s '/bin/bash' "${1}"
}

function getPackagesList {
    if [[ -z "${PACKAGES}" ]]; then
        echo "$(curl -sSL https://raw.githubusercontent.com/harrywyatt5/InstallLabPrerequisites/refs/heads/main/packages.txt)"
    else
        echo "${PACKAGES}"
    fi
}

function getGitHubPrefix {
    if [[ -z "${GITHUB_SSH_KEY}" ]]; then
        echo 'https://github.com/'
    else
        echo 'git@github.com:'
    fi
}

function getGitHubKeySwitch {
    if [[ -n "${GITHUB_SSH_KEY}" ]]; then
        echo "-c \"core.sshCommand=ssh -i ${GITHUB_SSH_KEY}\""
    fi
}

function getCoreCount {
    if [[ -z "${USE_CORE_COUNT}" ]]; then
        local total_sys_mem_kbs="$(cat /proc/meminfo | grep 'MemTotal' | awk '{ for(i=1; i<NF; i++) { if($i ~ /[0-9]/) print $i }}')"
        local total_page_mem_kbs="$(cat /proc/meminfo | grep 'SwapTotal' | awk '{ for(i=1; i<NF; i++) { if($i ~ /[0-9]/) print $i }}')"
        local total_cores="$(($total_sys_mem_kbs + $total_page_mem_kbs) / 2000000)"
        if [[ "${total_cores}" -eq 0 ]]; then
            echo 1
        elif [[ "${total_cores}" -gt "$(nproc)" ]]; then
            echo "$(nproc)"
        else
            echo "${total_cores}"
        fi
    else
        echo "${USE_CORE_COUNT}"
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

# Install and build sdformat9
run_as_install_user 'mkdir /tmp/sdformat9'
run_as_install_user "git clone $(getGitHubKeySwitch) -b ${SDFORMAT9_BRANCH} $(getGitHubPrefix)gazebosim/sdformat.git /tmp/sdformat9"
run_as_install_user "mkdir /tmp/sdformat9/build && cd /tmp/sdformat9/build && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local && make -j$(getCoreCount)"
