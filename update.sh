#!/bin/bash

################################################
# Script by François YoYae GINESTE - 10/08/2017
# Recode by LowKey for GoByte Core - 03/04/2018
# https://www.gobyte.network/
################################################

LOG_FILE=/tmp/gobyte_update.log

decho () {
  echo `date +"%H:%M:%S"` $1
  echo `date +"%H:%M:%S"` $1 >> $LOG_FILE
}

cat <<'FIG'
 ____        ____        _
/ ___|  ___ | __ ) _   _| |_ ___
| |  _ / _ \|  _ \| | | | __/ _ \
| |_| | (_) | |_) | |_| | ||  __/
\____|\___/|____/ \__, |\__\___|
                  |___/
FIG

echo -e "\nStarting GoByte masternode update. This will take a few minutes...\n"

## Check if root user

# Check if executed as root user
if [[ $EUID -ne 0 ]]; then
	echo -e "This script has to be run as \033[1mroot\033[0m user"
	exit 1
fi

## Ask for gobyte user name
read -e -p "Please enter the user name that runs GoByte Core /!\ case sensitive /!\ : " whoami

## Check if gobyte user exist
getent passwd $whoami > /dev/null 2&>1
if [ $? -ne 0 ]; then
	echo "$whoami user does not exist"
	exit 3
fi

## Stop active core
decho "Stoping active GoByte Core"
pkill -f gobyted  >> $LOG_FILE 2>&1

## Wait to kill properly
sleep 5

decho "Installing required packages."

# Add GoByte PPA
decho "Installing GoByte PPA..."
apt-get -y install software-properties-common >> $LOG_FILE 2>&1
add-apt-repository -y ppa:gobytecoin/gobyte >> $LOG_FILE 2>&1
apt-get -y update >> $LOG_FILE 2>&1

# Install required packages
decho "Installing base packages and dependencies..."
apt-get -y install sudo >> $LOG_FILE 2>&1
apt-get -y install wget >> $LOG_FILE 2>&1
apt-get -y install git >> $LOG_FILE 2>&1
apt-get -y install unzip >> $LOG_FILE 2>&1
apt-get -y install virtualenv >> $LOG_FILE 2>&1
apt-get -y install python-virtualenv >> $LOG_FILE 2>&1
apt-get -y install pwgen >> $LOG_FILE 2>&1

# Install GoByte Daemon
decho "Installing GoByte Core..."
apt-get -y install gobyte >> $LOG_FILE 2>&1

if [ "$whoami" != "root" ]; then
	path=/home/$whoami
else
	path=/root
fi

cd $path

# Relaunch core
decho "Relaunching GoByte Core"
sudo -H -u $whoami bash -c 'gobyted' >> $LOG_FILE 2>&1

## Update sentinel
decho "Setting up sentinel"

if [ ! -d "/home/$whoami/sentinel" ];
	decho 'Downloading sentinel...'
	#Install Sentinel
	git clone https://github.com/gobytecoin/sentinel.git /home/$whoami/sentinel >> $LOG_FILE 2>&1
	chown -R $whoami:$whoami /home/$whoami/sentinel >> $LOG_FILE 2>&1

	cd /home/$whoami/sentinel
	echo 'Setting up dependencies...'
	sudo -H -u $whoami bash -c 'virtualenv ./venv' >> $LOG_FILE 2>&1
	sudo -H -u $whoami bash -c './venv/bin/pip install -r requirements.txt' >> $LOG_FILE 2>&1
else
	decho "Sentinel already installed.";
fi	

#Setup crontab
echo "@reboot sleep 30 && gobyted" >> newCrontab
echo "* * * * * cd /home/$whoami/sentinel && ./venv/bin/python bin/sentinel.py >/dev/null 2>&1" >> newCrontab
crontab -u $whoami newCrontab >> $LOG_FILE 2>&1
rm newCrontab >> $LOG_FILE 2>&1

decho "Update finish !"
echo "Now, you need to finally restart your masternode in the following order: "
echo "Go to your windows/mac wallet on the Masternode tab."
echo "Select the updated masternode and then click on start-alias."
echo "Once completed please return to VPS and wait for the wallet to be synced."
echo "Then you can try the command 'gobyte-cli masternode status' to get the masternode status."

su $whoami
##End
