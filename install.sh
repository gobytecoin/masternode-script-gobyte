#!/bin/bash

################################################
# Script by François YoYae GINESTE - 03/04/2018
# Recode by LowKey for GoByte Core - 10/07/2018
# https://www.gobyte.network/
################################################

LOG_FILE=/tmp/install.log

decho () {
  echo `date +"%H:%M:%S"` $1
  echo `date +"%H:%M:%S"` $1 >> $LOG_FILE
}

error() {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"
  echo "Error on or near line ${parent_lineno}; exiting with status ${code}"
  exit "${code}"
}
trap 'error ${LINENO}' ERR

clear

cat <<'FIG'
 ____        ____        _
/ ___|  ___ | __ ) _   _| |_ ___
| |  _ / _ \|  _ \| | | | __/ _ \
| |_| | (_) | |_) | |_| | ||  __/
\____|\___/|____/ \__, |\__\___|
                  |___/
FIG

# Check for systemd
systemctl --version >/dev/null 2>&1 || { decho "systemd is required. Are you using Ubuntu 16.04?"  >&2; exit 1; }

# Check if executed as root user
if [[ $EUID -ne 0 ]]; then
	echo -e "This script has to be run as \033[1mroot\033[0m user"
	exit 1
fi

#print variable on a screen
decho "Make sure you double check before hitting enter !"

read -e -p "User that will run GoByte core /!\ case sensitive /!\ : " whoami
if [[ "$whoami" == "" ]]; then
	decho "WARNING: No user entered, exiting !!!"
	exit 3
fi
if [[ "$whoami" == "root" ]]; then
	decho "WARNING: user root entered? It is recommended to use a non-root user, exiting !!!"
	exit 3
fi
read -e -p "Server IP Address : " ip
if [[ "$ip" == "" ]]; then
	decho "WARNING: No IP entered, exiting !!!"
	exit 3
fi
read -e -p "Masternode Private Key (e.g. 7fjm9Yfdx9DD4J42r7rytMnbKUG1AzVB4fYZ71z4MVWRT9Nisty # THE KEY YOU GENERATED EARLIER) : " key
if [[ "$key" == "" ]]; then
	decho "WARNING: No masternode private key entered, exiting !!!"
	exit 3
fi
read -e -p "(Optional) Install Fail2ban? (Recommended) [Y/n] : " install_fail2ban
read -e -p "(Optional) Install UFW and configure ports? (Recommended) [Y/n] : " UFW

decho "Updating system and installing required packages."

# update package and upgrade Ubuntu
apt-get -y update >> $LOG_FILE 2>&1
# Add Berkely PPA
decho "Installing from GoByte PPA..."

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

#Install GoByte Daemon
decho "Installing GoByte Core..."
apt-get -y install gobyte >> $LOG_FILE 2>&1

if [[ ("$install_fail2ban" == "y" || "$install_fail2ban" == "Y" || "$install_fail2ban" == "") ]]; then
	decho "Optional installs : fail2ban"
	cd ~
	apt-get -y install fail2ban >> $LOG_FILE 2>&1
	systemctl enable fail2ban >> $LOG_FILE 2>&1
	systemctl start fail2ban >> $LOG_FILE 2>&1
fi

if [[ ("$UFW" == "y" || "$UFW" == "Y" || "$UFW" == "") ]]; then
	decho "Optional installs : ufw"
	apt-get -y install ufw >> $LOG_FILE 2>&1
	ufw allow ssh/tcp >> $LOG_FILE 2>&1
	ufw allow sftp/tcp >> $LOG_FILE 2>&1
	ufw allow 12455/tcp >> $LOG_FILE 2>&1
	ufw allow 12454/tcp >> $LOG_FILE 2>&1
	ufw default deny incoming >> $LOG_FILE 2>&1
	ufw default allow outgoing >> $LOG_FILE 2>&1
	ufw logging on >> $LOG_FILE 2>&1
	ufw --force enable >> $LOG_FILE 2>&1
fi

decho "Create user $whoami (if necessary)"
#desactivate trap only for this command
trap '' ERR
getent passwd $whoami > /dev/null 2&>1

if [ $? -ne 0 ]; then
	trap 'error ${LINENO}' ERR
	adduser --disabled-password --gecos "" $whoami >> $LOG_FILE 2>&1
else
	trap 'error ${LINENO}' ERR
fi

#Create gobyte.conf
decho "Setting up GoByte Core"
#Generating Random Passwords
user=`pwgen -s 16 1`
password=`pwgen -s 64 1`

echo 'Creating gobyte.conf...'
mkdir -p /home/$whoami/.gobytecore/
cat << EOF > /home/$whoami/.gobytecore/gobyte.conf
rpcuser=$user
rpcpassword=$password
rpcallowip=127.0.0.1
rpcport=12454
listen=1
server=1
daemon=1
maxconnections=24
masternode=1
masternodeprivkey=$key
externalip=$ip
addnode=81.17.56.122
addnode=103.72.163.84
addnode=103.72.163.225
addnode=81.17.56.88
addnode=62.212.88.40
addnode=62.212.88.48
addnode=81.17.56.120
addnode=62.212.89.246
addnode=103.72.163.96
addnode=103.72.162.222
addnode=54.38.72.115
addnode=94.23.156.183
addnode=94.23.162.60
addnode=5.135.59.35
addnode=145.239.94.161
addnode=158.69.113.97
EOF
chown -R $whoami:$whoami /home/$whoami

#Run gobyted as selected user
sudo -H -u $whoami bash -c 'gobyted' >> $LOG_FILE 2>&1

echo 'GoByte Core prepared and launched'

sleep 10

#Setting up coin

decho "Setting up sentinel"

echo 'Downloading sentinel...'
#Install Sentinel
git clone https://github.com/gobytecoin/sentinel.git /home/$whoami/sentinel >> $LOG_FILE 2>&1
chown -R $whoami:$whoami /home/$whoami/sentinel >> $LOG_FILE 2>&1

cd /home/$whoami/sentinel
echo 'Setting up dependencies...'
sudo -H -u $whoami bash -c 'virtualenv ./venv' >> $LOG_FILE 2>&1
sudo -H -u $whoami bash -c './venv/bin/pip install -r requirements.txt' >> $LOG_FILE 2>&1

#Setup crontab
echo "@reboot sleep 30 && gobyted" >> newCrontab
echo "* * * * * cd /home/$whoami/sentinel && ./venv/bin/python bin/sentinel.py >/dev/null 2>&1" >> newCrontab
crontab -u $whoami newCrontab >> $LOG_FILE 2>&1
rm newCrontab >> $LOG_FILE 2>&1

decho "Starting your masternode"
echo ""
echo "Now, you need to start your masternode in the following order: "
echo "1- Go to your Windows/Mac wallet and modify masternode.conf as required, then restart the wallet"
echo "2- From the masternode tab; Select the newly created masternode and click on start-alias."
echo "3- Once completed, return to the VPS and wait for the wallet to be synchronized."
echo "4- You may then try the command 'gobyte-cli masternode status' to get the masternode status."

su $whoami
