#!/bin/bash
set -e

echo "================================="
echo " LUNIT AUTOMATIC INSTALL"
echo "================================="


echo "[1/8] Updating system..."
sudo apt update -y


echo "[2/8] Installing tools..."
sudo apt install -y git wget curl unzip rclone


echo "[3/8] Connecting OneDrive..."

if ! rclone listremotes | grep -q "onedrive:"; then

    echo "OneDrive login required."
    echo "A browser will open."
    echo "Login with your Microsoft account."

    rclone config

fi


echo "[4/8] Downloading Lunit files..."

mkdir -p ~/lunit-files

rclone copy "onedrive:lunit" ~/lunit-files --progress


echo "Downloaded files:"
ls -lh ~/lunit-files



echo "[5/8] Installing Google Chrome..."

wget -O chrome.deb \
https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

sudo apt install -y ./chrome.deb

rm chrome.deb



echo "[6/8] Installing AnyDesk..."

wget -O anydesk.deb \
https://download.anydesk.com/linux/anydesk_7.1.0-1_amd64.deb

sudo apt install -y ./anydesk.deb

rm anydesk.deb



echo "[7/8] Installing TeamViewer..."

wget -O teamviewer.deb \
https://download.teamviewer.com/download/linux/teamviewer_amd64.deb

sudo apt install -y ./teamviewer.deb

rm teamviewer.deb



echo "[8/8] Starting Lunit installer..."

cd ~/lunit-files


if [ -f "lunit.run" ]; then

    chmod +x lunit.run
    ./lunit.run

else

    echo "ERROR: lunit.run not found"
    exit 1

fi


echo "================================="
echo " INSTALLATION COMPLETE"
echo "================================="
