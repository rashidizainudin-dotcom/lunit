#!/bin/bash


########################################
# LUNIT AUTOMATIC DEPLOYMENT
########################################


set +e


LOG="/var/log/lunit-deployment.log"


exec > >(tee -a "$LOG" >/dev/null)
exec 2>&1



SUCCESS=()
FAILED=()



########################################
# FUNCTIONS
########################################


task_start()
{

echo ""

echo "================================="
echo "$1"
echo "================================="

}



task_success()
{

echo "[✓] $1 completed"

SUCCESS+=("$1")

}



task_failed()
{

echo "[✗] $1 FAILED"

FAILED+=("$1")

}



########################################
# USER
########################################


REAL_USER=${SUDO_USER:-$USER}

USER_HOME=$(eval echo ~$REAL_USER)



echo ""
echo "================================="
echo " LUNIT INSTALLATION"
echo "================================="

echo "User : $REAL_USER"

echo "Home : $USER_HOME"





########################################
# SYSTEM UPDATE
########################################


task_start "System Update"



if apt update -y && apt upgrade -y

then

task_success "System update"

else

task_failed "System update"

fi






########################################
# DEPENDENCIES
########################################


task_start "Installing Dependencies"



PACKAGES=(

wget

curl

git

tar

unzip

docker.io

docker-compose-plugin

)



for PACKAGE in "${PACKAGES[@]}"
do


apt install -y "$PACKAGE" >/dev/null 2>&1


if [ $? -eq 0 ]

then

echo "[✓] $PACKAGE"

else

echo "[!] $PACKAGE failed"

fi


done





########################################
# RCLONE INSTALL
########################################


if command -v rclone >/dev/null 2>&1

then

echo "[✓] rclone exists"


else


echo "[!] Installing rclone"



curl https://rclone.org/install.sh | bash \
>/dev/null 2>&1



if command -v rclone >/dev/null 2>&1

then

echo "[✓] rclone installed"


else

task_failed "rclone"

fi


fi





systemctl enable docker >/dev/null 2>&1

systemctl start docker >/dev/null 2>&1



task_success "Dependencies"






########################################
# ONEDRIVE LOGIN
########################################


task_start "OneDrive Connection"



if rclone lsd onedrive: >/dev/null 2>&1

then


task_success "OneDrive already connected"



else



echo ""

echo "================================="

echo " OneDrive Login Required"

echo " Browser will open"

echo " Login Microsoft account"

echo "================================="

echo ""



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


task_start "Downloading Lunit Package"



mkdir -p "$USER_HOME/lunit-files"



rclone copy \
onedrive:lunit \
"$USER_HOME/lunit-files" \
--progress




if [ $? -eq 0 ]

then

task_success "Lunit package downloaded"


else

task_failed "Download package"

exit 1

fi






########################################
# CHECK FILES
########################################


task_start "Checking Installer Files"



cd "$USER_HOME/lunit-files"



FILES=(

google-chrome-stable_current_amd64.deb

anydesk_7.1.0-1_amd64.deb

teamviewer_15.70.4_amd64.deb

license-manager-5.2.1_9.14.1.tar

LunitINSIGHTMMG-1.2.3.4-0_GB.run

insight-board-1.2.3.tar

)



for FILE in "${FILES[@]}"

do


if [ -f "$FILE" ]

then

echo "[✓] Found $FILE"


else


echo "[✗] Missing $FILE"

FAILED+=("$FILE missing")


fi



done



task_success "File checking"
########################################
# INSTALL SOFTWARE
########################################


cd "$USER_HOME/lunit-files"





########################################
# GOOGLE CHROME
########################################


task_start "Installing Google Chrome"



apt install -y \
./google-chrome-stable_current_amd64.deb \
>/dev/null 2>&1



if [ $? -eq 0 ]

then

task_success "Google Chrome"

else

task_failed "Google Chrome"

fi






########################################
# ANYDESK
########################################


task_start "Installing AnyDesk"



apt install -y \
./anydesk_7.1.0-1_amd64.deb \
>/dev/null 2>&1



if [ $? -eq 0 ]

then

task_success "AnyDesk"

else

task_failed "AnyDesk"

fi






########################################
# TEAMVIEWER
########################################


task_start "Installing TeamViewer"



apt install -y \
./teamviewer_15.70.4_amd64.deb \
>/dev/null 2>&1



if [ $? -eq 0 ]

then

task_success "TeamViewer"

else

task_failed "TeamViewer"

fi







########################################
# LICENSE MANAGER
########################################


task_start "Installing License Manager"



tar xvf license-manager-5.2.1_9.14.1.tar \
>/dev/null 2>&1



cd license-manager-5.2.1_9.14.1



bash setup.sh \
>/dev/null 2>&1



if [ $? -eq 0 ]

then

task_success "License Manager"

else

task_failed "License Manager"

fi



cd "$USER_HOME/lunit-files"







########################################
# LUNIT MMG
########################################


task_start "Installing Lunit MMG"



chmod +x \
LunitINSIGHTMMG-1.1.10.4-0_GB.run



./LunitINSIGHTMMG-1.1.10.4-0_GB.run \
--compute-type cpu \
--timezone Asia/Kuala_Lumpur \
>/dev/null 2>&1



if [ $? -eq 0 ]

then

task_success "Lunit MMG"

else

task_failed "Lunit MMG"

fi






########################################
# INSIGHT BOARD
########################################


task_start "Installing Insight Board"



mkdir -p \
/opt/lunit/conf/insight-board



cp insight-board-1.2.3.tar \
/opt/lunit/conf/insight-board/



cd /opt/lunit/conf/insight-board





tar xvf insight-board-1.2.3.tar \
>/dev/null 2>&1





for F in docker_images/*
do

docker load -i "$F" \
>/dev/null 2>&1


done





rm -rf docker_images






mv template.docker-compose.yml docker-compose.yml






sed -i \
's/# profiles: \[mmg\]/profiles: [mmg]/' \
docker-compose.yml





sed -i \
's/dicom_gateway_mmg_default/insight-mmg-gateway_default/g' \
docker-compose.yml





docker network create \
dicom-gateway-cxr_default \
>/dev/null 2>&1 \
|| true




docker volume create \
--name=insight-cxr-gateway_db \
>/dev/null 2>&1 \
|| true




docker volume create \
--name=insight-dbt-gateway_db \
>/dev/null 2>&1 \
|| true






systemctl start docker



sleep 5





docker compose up -d \
>/dev/null 2>&1



if [ $? -eq 0 ]

then

task_success "Insight Board"

else

task_failed "Insight Board"

fi








########################################
# ANYDESK DISPLAY FIX
########################################


task_start "Configuring AnyDesk Display"



if [ -f /etc/gdm3/custom.conf ]

then


sed -i \
's/#WaylandEnable=false/WaylandEnable=false/' \
/etc/gdm3/custom.conf



task_success "AnyDesk Display"


else


task_failed "GDM configuration"


fi







########################################
# FINAL SUMMARY
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

echo "Log file:"

echo "$LOG"



echo ""

echo "================================="
echo " INSTALLATION FINISHED"
echo "================================="



echo ""

echo "Recommended:"
echo "sudo reboot"
