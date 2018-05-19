#!/usr/bin/env bash
###
# Purpose: To convert a standard Raspbian install into a functioning HMI over WiFi.
#
# Author: William Bailey
# Github URL: https://github.com/lightmaster/HMI
#
#
# Script is free and free to use, but please leave Author's information for credit.
#
#
#
###


## Check if run as root
scriptname=`basename "$0"`
if (( $EUID != 0 )); then
  echo "This script must be run as root (use \"sudo ./$scriptname\")"
  exit
fi

## Check if /home/pi/.HMIsetup exists
if [ -f "/home/pi/.HMIsetup" ]; then
  echo "Setup can only be run once, please reflash Raspbian if you need to start over."
  exit
fi

###################################
### Variables
echo "Please provide the following information so setup can run."
echo "Only run this script once!"
echo ""
read -e -p "IP Address: "       -i "192.168.57.99" IPAddress
read -e -p "Optimizer IP: "     -i "192.168.57.56" OptIP
read -e -p "Optimizer URL: "    -i "http://$OptIP/webcore/Boards.aspx" URL
read -e -p "Hostname: "         -i "Raptor" Hostname
#Raptor WiFi
echo ""
echo "Raptor WiFi:"
echo ""
read -e -p "WiFi SSID: "        -i "Raptor-2.4GHz" WiFi_SSID
read -e -p "WiFi Password: "    -i "raptor123" WiFi_passcode
#hotspot WiFi
echo ""
echo "Hotspot WiFi, leave blank if there is none."
echo ""
read -e -p "Hotspot SSID: "     -i "" Hotspot_SSID
read -e -p "Hotspot Password: " -i "" Hotspot_passcode
read -e -p "Country (US, CA): " -i "US" Country                   # 2 letter code US=United States, CA=Canada
read -e -p "Timezone City: "    -i "New_York" TimezoneCity        #Use _ for spaces. ie: New_York, Toronto, etc
###################################

##Change User Password
echo ""
echo "Changing user's password..."
passwd pi
echo ""
echo "Changing root's password..."
passwd root

## Setup a static IP fallback
echo "Setting static IP fallback..."
sleep 1s

cat <<EOF >> /etc/dhcpcd.conf
# define static profile
profile static_wlan0
static ip_address=$IPAddress       # or whatever IP you want to give it
static routers=192.168.57.1
static domain_name_server=192.168.57.1

# fallback to static profile on wlan0
interface wlan0
fallback static_wlan0
EOF

## WiFi SSID and password
echo "Setting WiFi connection info..."
sleep 1s

if [[ "$Hotspot_SSID" != "" ]]; then
#Hostpot is provided
cat <<EOF >> /etc/wpa_supplicant/wpa_supplicant.conf
network={
  ssid="$Hotspot_SSID"
  psk="$Hotspot_passcode"
  priority=2
}

network={
  ssid="$WiFi_SSID"               #WiFi Network Name
  psk="$WiFi_passcode"            #WiFi password
  priority=1
}
EOF
else
#Hotspot is not provided
cat <<EOF >> /etc/wpa_supplicant/wpa_supplicant.conf
network={
  ssid="$WiFi_SSID"               #WiFi Network Name
  psk="$WiFi_passcode"            #WiFi password
  priority=1
}
EOF
fi

echo "restarting WiFi..."
wpa_cli -i wlan0 reconfigure
sleep 30s

## Check for updates and install unclutter
echo "Removing Raspbian Bloat..."
sleep 1s

pkgToRemoveListFull="libreoffice* gpicview wolfram-engine scratch nuscratch sonic-pi idle3 smartsim minecraft-pi python-minecraftpi python3-minecraftpi"
pkgToRemoveList=""
for pkgToRemove in $(echo $pkgToRemoveListFull); do
  $(dpkg --status $pkgToRemove &> /dev/null)
  if [[ $? -eq 0 ]]; then
    pkgToRemoveList="$pkgToRemoveList $pkgToRemove"
  fi
done
apt purge -y $pkgToRemoveList

#apt purge -y libreoffice* gpicview wolfram-engine scratch nuscratch sonic-pi idle3 smartsim minecraft-pi python-minecraftpi python3-minecraftpi > /dev/null
apt autoremove -y
apt autoclean -y

if ping -q -c 1 -W 1 google.com >/dev/null; then
  echo "Connected to internet, updating Raspbian OS..."
  sleep 1s
  apt update && apt -y dist-upgrade
  apt install -y unclutter
  rpi-update
else
  echo "Not connected to the internet, please update Raspbian later when you are connected..."
  sleep 1s
fi

## Setup raspi-config
echo "Setting up raspi-config settings and locale information..."
sleep 1s

raspi-config nonint do_hostname $Hostname
raspi-config nonint do_vnc 0
raspi-config nonint do_ssh 0
raspi-config nonint do_boot_behaviour B4
raspi-config nonint do_boot_splash 1
raspi-config nonint do_memory_split 256
raspi-config nonint do_wifi_country $Country
raspi-config nonint do_change_locale en_$Country.UTF-8
raspi-config nonint do_change_timezone America/$TimezoneCity

## Set Chromium as default browser
echo "Setting Chromium as default browser..."
sleep 1s

xdg-settings set default-web-browser chromium-browser.desktop
su -c 'xdg-settings set default-web-browser chromium-browser.desktop' pi

## Disable screen blanking and autolaunch chromium
echo "Disabling screen blanking and setting Chromium to autostart on reboot..."
sleep 1s

cat <<EOF >> /home/pi/.config/lxsession/LXDE-pi/autostart
@xset s noblank
@xset s off
@xset -dpms
@sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' /home/pi/.config/chromium/'Local State'
@sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' /home/pi/.config/chromium/Default/Preferences
@sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' /home/pi/.config/chromium/Default/Preferences
sleep 10s
@chromium-browser --noerrdialogs --no-first-run --incognito --no-default-browser-check --kiosk --fast --fast-start --disable-infobars --disable-session-crashed-bubble --disable-restore-session-state $URL
EOF

## Schedule a reboot every night
#echo "Scheduling a reboot for each night..."
#sleep 1s
#
#croncmd="reboot"
#cronjob="0 0 * * * $croncmd"
#( crontab -l | grep -v -F "$croncmd" ; echo "$cronjob" ) | crontab -

## Touch /home/pi/.HMIsetup to prevent running script again
touch /home/pi/.HMIsetup

## Reboot after running
echo "Rebooting system in 5 seconds..."
sleep 5s
reboot
