#!/usr/bin/env bash
set -e

# -- Parameters ---
# ROS2_GPG_KEY can be used to manually set a ros2 GPG key in base64 (optional)
# USE_CORE_COUNT is how many cores to use to operate the compilation (optional)
# PACKAGES is a newline-separated list of packages to get from apt (optional)
# GITHUB_SSH_KEY will use SSH rather than HTTPS to clone Git packages if set, offering that SSH key to GitHub (optional)
USE_ROS2_BRANCH="${USE_ROS2_BRANCH:-main}"
INSTALL_USER="${INSTALL_USER:-$(logname)}"
SDFORMAT9_BRANCH="${SDFORMAT9_BRANCH:-sdformat9_9.8.0}"
GAZEBO_CLASSIC_BRANCH="${GAZEBO_CLASSIC_BRANCH:-gazebo11}"
GAZEBO_PKGS_BRANCH="${GAZEBO_PKGS_BRANCH:-ros2}"
TURTLEBOT_SIMULATIONS_BRANCH="${TURTLEBOT_SIMULATIONS_BRANCH:-humble}"
ROS2_CONTROL_BRANCH="${ROS2_CONTROL_BRANCH:-humble}"

function getGPGKey {
    if [[ -z "${ROS2_GPG_KEY}" ]]; then
        curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key
    else
        printf '%s' "${ROS2_GPG_KEY}" | base64 -d
    fi 
}

function run_as_install_user {
    su - "${INSTALL_USER}" -s /bin/bash -c "${1}"
}

function getPackagesList {
    if [[ -z "${PACKAGES}" ]]; then
        curl -sSL https://raw.githubusercontent.com/harrywyatt5/InstallLabPrerequisites/refs/heads/main/packages.txt
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
        local total_cores="$((($total_sys_mem_kbs + $total_page_mem_kbs) / 3000000))"
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

source /etc/os-release
if [[ "${UBUNTU_CODENAME}" != 'jammy' ]]; then
    read -p 'WARN: This script was only designed for Ubuntu 22.04, so may not work. Press ENTER to continue...'
fi

# Install virt-what to check if we are running on a hypervisor and curl to download the required dependency list
add-apt-repository universe -y
apt update
apt install virt-what curl -y

if [[ -z "$(virt-what)" ]]; then
    read -p 'WARN: This system is not a virtual machine. It is highly recommended to run this script in a VM. Press ENTER to continue...'
fi

# Configure Ros2 repo
getGPGKey > /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} ${USE_ROS2_BRANCH}" > /etc/apt/sources.list.d/ros2.list
apt update

# Install additional packages
getPackagesList | xargs apt install -y

# Install and build sdformat9
run_as_install_user 'mkdir /tmp/sdformat9'
run_as_install_user "git clone $(getGitHubKeySwitch) -b ${SDFORMAT9_BRANCH} $(getGitHubPrefix)gazebosim/sdformat.git /tmp/sdformat9"
run_as_install_user "mkdir /tmp/sdformat9/build && cd /tmp/sdformat9/build && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local && make -j$(getCoreCount)"
cd /tmp/sdformat9/build
make install
cd
# Clean up sdformat9 install location
rm -r '/tmp/sdformat9'

# Install and build Gazebo Classic
run_as_install_user 'mkdir /tmp/gc'
run_as_install_user "git clone $(getGitHubKeySwitch) -b ${GAZEBO_CLASSIC_BRANCH} $(getGitHubPrefix)gazebosim/gazebo-classic /tmp/gc"
run_as_install_user "mkdir /tmp/gc/build && cd /tmp/gc/build && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local && make -j$(getCoreCount)"
cd /tmp/gc/build
make install
cd
rm -r /tmp/gc

# Set up user's bashrc
USR_SOURCE_SCRIPTS="
source /opt/ros/humble/setup.bash
source /usr/share/colcon_cd/function/colcon_cd.sh
source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash
export _colcon_cd_root=~/ros_additional_libraries
source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash
source /usr/local/share/gazebo/setup.bash
"
run_as_install_user "echo ${USR_SOURCE_SCRIPTS} >> ~/.bashrc"
run_as_install_user "
mkdir ~/ros_additional_libraries
mkdir ~/ros_additional_libraries/src
cd ~/ros_additional_libraries/src
mkdir gazebo_ros_pkgs
mkdir turtlebot3_simulations
mkdir gazebo_ros2_control
"
run_as_install_user "git clone $(getGitHubKeySwitch) -b ${GAZEBO_PKGS_BRANCH} $(getGitHubPrefix)ros-simulation/gazebo_ros_pkgs ~/ros_additional_libraries/src/gazebo_ros_pkgs"
run_as_install_user "git clone $(getGitHubKeySwitch) -b ${TURTLEBOT_SIMULATIONS_BRANCH} $(getGitHubPrefix)ROBOTIS-GIT/turtlebot3_simulations ~/ros_additional_libraries/src/turtlebot3_simulations"
run_as_install_user "git clone $(getGitHubKeySwitch) -b ${ROS2_CONTROL_BRANCH} $(getGitHubPrefix)ros-controls/gazebo_ros2_control ~/ros_additional_libraries/src/gazebo_ros2_control"
run_as_install_user "${USR_SOURCE_SCRIPTS} export MAKEFLAGS='-j$(getCoreCount)' && cd ~/ros_additional_libraries && colcon build --symlink-install"
run_as_install_user "
mkdir ~/comp_robot_ws/
mkdir ~/comp_robot_ws/src
echo 'source ~/comp_robot_ws/install/setup.bash' >> ~/.bashrc
echo 'source ~/ros_additional_libraries/install/setup.bash' >> ~/.bashrc
sed -i 's/export _colcon_cd_root=.+$/export _colcon_cd_root=~/comp_robot_ws' ~/.bashrc
"
echo 'Done! You should be able to clone the labs into ~/comp_robot_ws/src and build and run them!'
