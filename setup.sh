#!/bin/bash
set -e

echo "Starting Lunit installation"

# Become root check
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo"
    exit
fi


# Update system
apt update
apt upgrade -y


# Install dependencies
apt install -y docker.io docker-compose wget curl tar unzip


# Install Chrome
apt install -y /home/lunit/Downloads/google-chrome-stable_current_amd64.deb


# Install AnyDesk
apt install -y /home/lunit/Downloads/anydesk_7.1.0-1_amd64.deb


# Install TeamViewer
apt install -y /home/lunit/Downloads/teamviewer_15.70.4_amd64.deb



#################################
# License Manager
#################################

cd /home/lunit/license-manager

tar xvf license-manager-5.2.1_9.14.1.tar

cd license-manager-5.2.1_9.14.1

bash setup.sh



#################################
# Install MMG
#################################

chmod +x LunitINSIGHTMMG-1.1.10.4-0_GB.run

./LunitINSIGHTMMG-1.1.10.4-0_GB.run \
--compute-type cpu \
--timezone Asia/Kuala_Lumpur



#################################
# Insight Board
#################################

mkdir -p /opt/lunit/conf/insight-board

cp insight-board-1.2.3.tar \
/opt/lunit/conf/insight-board/


cd /opt/lunit/conf/insight-board

tar xvf insight-board-1.2.3.tar


for F in docker_images/*; do
    docker load -i "$F"
done


rm -rf docker_images



cp template.docker-compose.yml docker-compose.yml


docker compose up -d



#################################
# Disable Wayland for AnyDesk
#################################

sed -i 's/#WaylandEnable=false/WaylandEnable=false/' \
/etc/gdm3/custom.conf



systemctl restart gdm3


echo "Lunit installation complete"
