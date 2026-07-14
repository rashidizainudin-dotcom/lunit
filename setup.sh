#!/bin/bash

set -e

LOG="/var/log/lunit-deployment.log"

exec > >(tee -a $LOG)
exec 2>&1


SUCCESS=()
FAILED=()


function task_start {
    echo ""
    echo "================================="
    echo "$1"
    echo "================================="
}


function task_success {
    echo "[✓] $1 completed"
    SUCCESS+=("$1")
}


function task_failed {
    echo "[✗] $1 FAILED"
    FAILED+=("$1")
}



########################################
# USER
########################################

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)


echo "Deploy user : $REAL_USER"
echo "Home folder : $USER_HOME"



########################################
# SYSTEM UPDATE
########################################

task_start "System Update"

if apt update && apt upgrade -y
then
    task_success "System update"
else
    task_failed "System update"
fi



########################################
# 2. INSTALL DEPENDENCIES
########################################

progress "Installing dependencies"


apt install -y \
wget \
curl \
git \
tar \
unzip \
docker.io \
docker-compose-plugin \
>/dev/null 2>&1 \
|| true


# Install rclone separately

if command -v rclone >/dev/null 2>&1

then

    echo "[✓] rclone already installed"

else

    echo "[!] rclone not found, installing manually"


    curl https://rclone.org/install.sh | bash \
    >/dev/null 2>&1 \
    || failed "rclone installation"


fi



systemctl enable docker >/dev/null 2>&1 || true

systemctl start docker >/dev/null 2>&1 || true



success "Dependencies installed"



########################################
# ONEDRIVE
########################################

task_start "OneDrive Connection"


if rclone lsd onedrive: >/dev/null 2>&1

then

task_success "OneDrive connected"

else

echo "OneDrive login required"

rclone config


if rclone lsd onedrive: >/dev/null 2>&1

then
task_success "OneDrive login"

else
task_failed "OneDrive login"
exit 1

fi

fi



########################################
# DOWNLOAD PACKAGE
########################################

task_start "Download Lunit Package"


mkdir -p "$USER_HOME/lunit-files"


if rclone copy \
onedrive:lunit \
"$USER_HOME/lunit-files" \
--progress

then

task_success "Lunit package downloaded"

else

task_failed "Lunit package download"
exit 1

fi



########################################
# CHECK FILES
########################################

task_start "Check Installer Files"


FILES=(
google-chrome-stable_current_amd64.deb
anydesk_7.1.0-1_amd64.deb
teamviewer_15.70.4_amd64.deb
license-manager-5.2.1_9.14.1.tar
LunitINSIGHTMMG-1.1.10.4-0_GB.run
insight-board-1.2.3.tar
)


cd "$USER_HOME/lunit-files"


for FILE in "${FILES[@]}"
do

if [ -f "$FILE" ]

then

echo "[✓] Found $FILE"

else

echo "[✗] Missing $FILE"
exit 1

fi

done


task_success "Installer files verified"



########################################
# SOFTWARE INSTALL
########################################

task_start "Install Chrome"


if apt install -y ./google-chrome-stable_current_amd64.deb

then
task_success "Google Chrome deployed"
else
task_failed "Google Chrome"
fi




task_start "Install AnyDesk"


if apt install -y ./anydesk_7.1.0-1_amd64.deb

then
task_success "AnyDesk deployed"
else
task_failed "AnyDesk"
fi




task_start "Install TeamViewer"


if apt install -y ./teamviewer_15.70.4_amd64.deb

then
task_success "TeamViewer deployed"
else
task_failed "TeamViewer"
fi



########################################
# LICENSE MANAGER
########################################

task_start "License Manager"


tar xvf license-manager-5.2.1_9.14.1.tar


cd license-manager-5.2.1_9.14.1


if bash setup.sh

then
task_success "License Manager deployed"
else
task_failed "License Manager"
fi


cd "$USER_HOME/lunit-files"



########################################
# MMG
########################################

task_start "Lunit MMG"


chmod +x LunitINSIGHTMMG-1.1.10.4-0_GB.run


if ./LunitINSIGHTMMG-1.1.10.4-0_GB.run \
--compute-type cpu \
--timezone Asia/Kuala_Lumpur

then

task_success "Lunit MMG deployed"

else

task_failed "Lunit MMG"

fi




########################################
# INSIGHT BOARD
########################################

task_start "Insight Board"


mkdir -p /opt/lunit/conf/insight-board


cp insight-board-1.2.3.tar \
/opt/lunit/conf/insight-board/


cd /opt/lunit/conf/insight-board


tar xvf insight-board-1.2.3.tar



for F in docker_images/*
do
docker load -i "$F"
done


rm -rf docker_images


mv template.docker-compose.yml docker-compose.yml


sed -i \
's/# profiles: \[mmg\]/profiles: [mmg]/' \
docker-compose.yml


sed -i \
's/dicom_gateway_mmg_default/insight-mmg-gateway_default/g' \
docker-compose.yml



docker network create dicom-gateway-cxr_default || true


docker volume create \
--name=insight-cxr-gateway_db || true


docker volume create \
--name=insight-dbt-gateway_db || true



if docker compose up -d

then

task_success "Insight Board deployed"

else

task_failed "Insight Board"

fi




########################################
# ANYDESK DISPLAY
########################################

task_start "AnyDesk Display Fix"


sed -i \
's/#WaylandEnable=false/WaylandEnable=false/' \
/etc/gdm3/custom.conf


task_success "AnyDesk display configured"



########################################
# SUMMARY
########################################


echo ""
echo "================================="
echo " DEPLOYMENT SUMMARY"
echo "================================="


echo ""
echo "SUCCESS:"
printf '%s\n' "${SUCCESS[@]}"


echo ""
echo "FAILED:"
printf '%s\n' "${FAILED[@]}"


echo ""
echo "Log saved:"
echo "$LOG"


echo ""
echo "Deployment completed."
echo "Reboot recommended."
