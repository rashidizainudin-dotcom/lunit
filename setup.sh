#!/bin/bash
set -e

echo "================================="
echo " LUNIT AUTOMATIC INSTALLATION"
echo "================================="


# Detect real user
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)

echo "Running as: $REAL_USER"
echo "Home: $USER_HOME"



#################################
# System update
#################################

echo "[1/10] Updating system..."

apt update -y
apt upgrade -y



#################################
# Install dependencies
#################################

echo "[2/10] Installing dependencies..."

apt install -y \
wget \
curl \
tar \
unzip \
git \
rclone \
docker.io \
docker-compose


systemctl enable docker
systemctl start docker



#################################
# OneDrive login check
#################################

echo "[3/10] Checking OneDrive connection..."

if ! rclone listremotes | grep -q "^onedrive:"; then

    echo ""
    echo "================================="
    echo " OneDrive login required"
    echo " Browser will open"
    echo " Login with Microsoft account"
    echo "================================="
    echo ""

    rclone config

fi


echo "Testing OneDrive..."

if ! rclone lsd onedrive: >/dev/null 2>&1; then

    echo ""
    echo "ERROR: OneDrive login failed."
    echo "Installation stopped."
    exit 1

fi


echo "OneDrive connected."



#################################
# Download files
#################################

echo "[4/10] Downloading Lunit package..."

mkdir -p "$USER_HOME/lunit-files"

chown -R $REAL_USER:$REAL_USER "$USER_HOME/lunit-files"


rclone copy \
"onedrive:lunit" \
"$USER_HOME/lunit-files" \
--progress



cd "$USER_HOME/lunit-files"


echo "Files downloaded:"
ls -lh



#################################
# Install Chrome
#################################

echo "[5/10] Installing Google Chrome..."

apt install -y \
./google-chrome-stable_current_amd64.deb



#################################
# Install AnyDesk
#################################

echo "[6/10] Installing AnyDesk..."

apt install -y \
./anydesk_7.1.0-1_amd64.deb



#################################
# Install TeamViewer
#################################

echo "[7/10] Installing TeamViewer..."

apt install -y \
./teamviewer_15.70.4_amd64.deb



#################################
# License Manager
#################################

echo "[8/10] Installing License Manager..."

tar xvf license-manager-5.2.1_9.14.1.tar


cd license-manager-5.2.1_9.14.1


bash setup.sh


cd "$USER_HOME/lunit-files"



#################################
# Install INSIGHT MMG
#################################

echo "Installing Lunit INSIGHT MMG..."


chmod +x LunitINSIGHTMMG-1.1.10.4-0_GB.run


./LunitINSIGHTMMG-1.1.10.4-0_GB.run \
--compute-type cpu \
--timezone Asia/Kuala_Lumpur




#################################
# Install Insight Board
#################################

echo "Installing Insight Board..."


mkdir -p /opt/lunit/conf/insight-board


cp insight-board-1.2.3.tar \
/opt/lunit/conf/insight-board/


cd /opt/lunit/conf/insight-board


tar xvf insight-board-1.2.3.tar



for F in docker_images/*;
do
    docker load -i "$F"
done



rm -rf docker_images



mv template.docker-compose.yml docker-compose.yml



#################################
# Docker setup
#################################

echo "Preparing Docker..."


docker network create dicom-gateway-cxr_default || true


docker volume create \
--name=insight-cxr-gateway_db || true


docker volume create \
--name=insight-dbt-gateway_db || true



docker compose up -d




#################################
# AnyDesk display fix
#################################

echo "Configuring AnyDesk display..."


sed -i \
's/#WaylandEnable=false/WaylandEnable=false/' \
/etc/gdm3/custom.conf




#################################
# Complete
#################################

echo ""
echo "================================="
echo " LUNIT INSTALL COMPLETE"
echo "================================="

echo ""
echo "Open:"
echo "http://localhost:1948/"
echo "http://localhost:81/manager/"
echo "http://localhost:9000/admin/"
echo "http://localhost:81/admin/"
echo "http://localhost:3000"


echo ""
echo "Grafana:"
echo "username: lunit"
echo "password: lunitinsight"


echo ""
echo "Please reboot:"
echo "sudo reboot"
