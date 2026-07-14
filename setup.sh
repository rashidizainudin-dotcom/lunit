#!/bin/bash

########################################
# LUNIT AUTOMATIC DEPLOYMENT
########################################

set +e

# Everything below (apt, /var/log, /opt/lunit, systemctl, docker) needs
# root. Check explicitly and fail with a clear message instead of
# letting the first apt/log-write fail with a confusing permission error.
if [ "$EUID" -ne 0 ]
then
    echo "This script must be run as root. Try: sudo bash $0"
    exit 1
fi

# Force apt to never wait on an interactive prompt (debconf dialogs,
# "which services should be restarted" from needrestart, etc). This
# is what most commonly makes an "apt install" step look like it's
# frozen at N minutes elapsed when it's actually stuck waiting for
# input that will never come in an unattended/backgrounded run.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

LOG="/var/log/lunit-deployment.log"

# FIX #2: show output on the terminal AND log it (previously tee's
# stdout was sent to /dev/null, so nothing appeared on screen).
exec > >(tee -a "$LOG") 2>&1


SUCCESS=()
FAILED=()

# Where the live spinner gets drawn. We write it straight to the
# controlling terminal (bypassing the tee above) so the spinner's
# carriage-return animation never gets smeared across the log file.
# Falls back to /dev/null if there's no terminal (e.g. run from cron).
if : > /dev/tty 2>/dev/null
then
    TTY_DEV="/dev/tty"
else
    TTY_DEV="/dev/null"
fi


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

# Runs a command in the background and shows a live spinner with
# elapsed seconds while it works. Full command output (stdout+stderr)
# is appended to $LOG so nothing is lost; the spinner itself goes to
# the terminal only. Returns the command's real exit code.
#
# Usage: spin_run "Doing thing" some_command --with args
spin_run()
{
    local desc="$1"
    shift

    {
        echo ""
        echo "=== $desc ==="
    } >> "$LOG"

    "$@" >> "$LOG" 2>&1 < /dev/null &
    local pid=$!

    local spin='|/-\'
    local i=0
    local start=$SECONDS

    while kill -0 "$pid" 2>/dev/null
    do
        i=$(( (i + 1) % 4 ))
        printf "\r  [%s] %s (%ds elapsed)   " "${spin:$i:1}" "$desc" "$(( SECONDS - start ))" > "$TTY_DEV"
        sleep 0.2
    done

    wait "$pid"
    local status=$?
    local elapsed=$(( SECONDS - start ))

    if [ $status -eq 0 ]
    then
        printf "\r  [✓] %s (%ds)                    \n" "$desc" "$elapsed" > "$TTY_DEV"
    else
        printf "\r  [✗] %s FAILED (%ds)             \n" "$desc" "$elapsed" > "$TTY_DEV"
    fi

    return $status
}

# Helper for steps that must stop the whole deployment on failure
task_failed_fatal()
{
    task_failed "$1"
    echo ""
    echo "================================="
    echo " DEPLOYMENT ABORTED: $1"
    echo "================================="
    echo ""
    echo "SUCCESS:"
    printf '%s\n' "${SUCCESS[@]}"
    echo ""
    echo "FAILED:"
    printf '%s\n' "${FAILED[@]}"
    exit 1
}


########################################
# USER
########################################

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~"$REAL_USER")

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

if spin_run "System update (apt update && apt upgrade)" bash -c "apt update -y && apt upgrade -y"
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
    docker-compose
    docker-compose-plugin
)

DEP_FAILED=0

for PACKAGE in "${PACKAGES[@]}"
do
    if spin_run "Installing $PACKAGE" apt install -y "$PACKAGE"
    then
        # Show the installed version right on the tick line for the
        # Docker-related packages, so it's obvious what actually
        # landed on the machine (useful for support/debugging later).
        VERSION_INFO=""
        case "$PACKAGE" in
            docker.io)
                VERSION_INFO=$(docker --version 2>/dev/null)
                ;;
            docker-compose)
                VERSION_INFO=$(docker-compose --version 2>/dev/null)
                ;;
            docker-compose-plugin)
                VERSION_INFO=$(docker compose version 2>/dev/null)
                ;;
        esac

        if [ -n "$VERSION_INFO" ]
        then
            echo "[✓] $PACKAGE — $VERSION_INFO"
        else
            echo "[✓] $PACKAGE"
        fi
    else
        echo "[!] $PACKAGE failed"
        DEP_FAILED=1
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

    spin_run "Installing rclone" bash -c "curl -s https://rclone.org/install.sh | bash"

    if command -v rclone >/dev/null 2>&1
    then
        echo "[✓] rclone installed"
    else
        # FIX #4: rclone is required for everything downstream
        # (OneDrive login + package download), so a failed install
        # must stop the deployment here instead of limping on into
        # a broken `rclone config` / `rclone lsd` step.
        task_failed_fatal "rclone install"
    fi
fi

systemctl enable docker >/dev/null 2>&1
systemctl start docker >/dev/null 2>&1

if [ "$DEP_FAILED" -eq 0 ]
then
    task_success "Dependencies"
else
    task_failed "Dependencies (one or more packages failed, see above)"
fi


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
    echo " Login with your Microsoft account"
    echo "================================="
    echo ""

    rclone config

    # FIX #2: explicitly wait for the person to confirm they've
    # finished the browser-based auth flow before we try to verify
    # the connection. rclone config normally blocks until you exit
    # the interactive menu, but this makes the handoff explicit
    # instead of silently racing ahead.
    echo ""
    read -rp "Press [Enter] once you have finished authenticating with OneDrive... "
    echo ""

    if rclone lsd onedrive: >/dev/null 2>&1
    then
        task_success "OneDrive login"
    else
        task_failed_fatal "OneDrive login"
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
    task_failed_fatal "Download package"
fi


########################################
# CHECK FILES
########################################

task_start "Checking Installer Files"

cd "$USER_HOME/lunit-files" || task_failed_fatal "cd into $USER_HOME/lunit-files"

# FIX #1: corrected MMG installer version to match the real file
# (1.1.10.4-0), and this is now the single source of truth used
# later in the "LUNIT MMG" step too, so the two can't drift apart.
MMG_RUN_FILE="LunitINSIGHTMMG-1.1.10.4-0_GB.run"

FILES=(
    google-chrome-stable_current_amd64.deb
    anydesk_7.1.0-1_amd64.deb
    teamviewer_15.70.4_amd64.deb
    license-manager-5.2.1_9.14.1.tar
    "$MMG_RUN_FILE"
    insight-board-1.2.3.tar
)

MISSING=0

for FILE in "${FILES[@]}"
do
    if [ -f "$FILE" ]
    then
        echo "[✓] Found $FILE"
    else
        echo "[✗] Missing $FILE"
        FAILED+=("$FILE missing")
        MISSING=1
    fi
done

# FIX #3: previously a missing file was only recorded, and the
# script pressed on into `apt install -y ./<missing file>`, which
# fails on a nonexistent path. Now we stop cleanly here and tell
# the person exactly what's missing before touching any installer.
if [ "$MISSING" -eq 1 ]
then
    task_failed_fatal "File checking (one or more installer files are missing from $USER_HOME/lunit-files)"
else
    task_success "File checking"
fi


########################################
# INSTALL SOFTWARE
########################################

cd "$USER_HOME/lunit-files" || task_failed_fatal "cd into $USER_HOME/lunit-files"


########################################
# GOOGLE CHROME
########################################

task_start "Installing Google Chrome"

if spin_run "Installing Google Chrome" apt install -y ./google-chrome-stable_current_amd64.deb
then
    task_success "Google Chrome"
else
    task_failed "Google Chrome"
fi


########################################
# ANYDESK
########################################

task_start "Installing AnyDesk"

if spin_run "Installing AnyDesk" apt install -y ./anydesk_7.1.0-1_amd64.deb
then
    task_success "AnyDesk"
else
    task_failed "AnyDesk"
fi


########################################
# TEAMVIEWER
########################################

task_start "Installing TeamViewer"

if spin_run "Installing TeamViewer" apt install -y ./teamviewer_15.70.4_amd64.deb
then
    task_success "TeamViewer"
else
    task_failed "TeamViewer"
fi


########################################
# LICENSE MANAGER
########################################

task_start "Installing License Manager"

spin_run "Extracting license manager archive" tar xvf license-manager-5.2.1_9.14.1.tar

cd license-manager-5.2.1_9.14.1 || task_failed_fatal "cd into license-manager-5.2.1_9.14.1"

if spin_run "Running license manager setup" bash setup.sh
then
    task_success "License Manager"
else
    task_failed "License Manager"
fi

cd "$USER_HOME/lunit-files" || task_failed_fatal "cd back into $USER_HOME/lunit-files"


########################################
# LUNIT MMG
########################################

task_start "Installing Lunit MMG"

chmod +x "$MMG_RUN_FILE"

if spin_run "Running Lunit MMG installer" ./"$MMG_RUN_FILE" --compute-type cpu --timezone Asia/Kuala_Lumpur
then
    task_success "Lunit MMG"
else
    task_failed "Lunit MMG"
fi


########################################
# INSIGHT BOARD
########################################

task_start "Installing Insight Board"

mkdir -p /opt/lunit/conf/insight-board

# Move (not copy) the tarball into place, matching the manual
# procedure — leaves lunit-files clean instead of a duplicate copy.
mv "$USER_HOME/lunit-files/insight-board-1.2.3.tar" /opt/lunit/conf/insight-board/

cd /opt/lunit/conf/insight-board || task_failed_fatal "cd into /opt/lunit/conf/insight-board"

spin_run "Extracting Insight Board archive" tar xvf insight-board-1.2.3.tar -C /opt/lunit/conf/insight-board

for F in /opt/lunit/conf/insight-board/docker_images/*
do
    spin_run "Loading docker image: $(basename "$F")" docker load -i "$F"
done

rm -rf /opt/lunit/conf/insight-board/docker_images/

COMPOSE_FILE="/opt/lunit/conf/insight-board/docker-compose.yml"

# The archive doesn't always name this file the same way — sometimes
# it extracts straight to docker-compose.yml, sometimes it needs
# renaming from template.docker-compose.yml. Handle both instead of
# assuming one, so a naming mismatch never causes a silent no-op.
if [ -f "$COMPOSE_FILE" ]
then
    echo "[i] docker-compose.yml already present at $COMPOSE_FILE"
else
    TEMPLATE_COMPOSE_FILE=$(find /opt/lunit/conf/insight-board -maxdepth 4 -iname 'template.docker-compose.yml' | head -n1)

    if [ -z "$TEMPLATE_COMPOSE_FILE" ]
    then
        task_failed_fatal "Insight Board (no docker-compose.yml or template.docker-compose.yml found after extraction — check the tar contents)"
    fi

    mv "$TEMPLATE_COMPOSE_FILE" "$COMPOSE_FILE"

    if [ ! -f "$COMPOSE_FILE" ]
    then
        task_failed_fatal "Insight Board (docker-compose.yml missing after mv)"
    fi
fi

sed -i 's/# profiles: \[mmg\]/profiles: [mmg]/' "$COMPOSE_FILE"

# networks.default.mmg_gateway.name:
#   dicom_gateway_mmg_default  ->  insight-mmg-gateway_default
sed -i 's/dicom_gateway_mmg_default/insight-mmg-gateway_default/g' "$COMPOSE_FILE"

# Verify the substitution actually happened instead of assuming it
# did — sed exits 0 even when nothing matched.
if grep -q 'insight-mmg-gateway_default' "$COMPOSE_FILE"
then
    echo "[✓] docker-compose.yml network name fixed (insight-mmg-gateway_default)"
else
    echo "[✗] docker-compose.yml network name fix did NOT apply — check $COMPOSE_FILE manually"
    FAILED+=("docker-compose.yml network name fix")
fi

if grep -q 'dicom_gateway_mmg_default' "$COMPOSE_FILE"
then
    echo "[!] Warning: 'dicom_gateway_mmg_default' still appears elsewhere in $COMPOSE_FILE"
fi

docker network create dicom-gateway-cxr_default >/dev/null 2>&1 || true

docker volume create --name=insight-cxr-gateway_db >/dev/null 2>&1 || true

docker volume create --name=insight-dbt-gateway_db >/dev/null 2>&1 || true

systemctl start docker

sleep 5

if spin_run "Starting Insight Board containers" docker compose up -d
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
    sed -i 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
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
