#!/bin/bash

################################################
# Script by François YoYae GINESTE - 03/04/2018
# Recode for GoByte - 10/08/2017
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
decho "Installing bitcoin PPA..."

apt-get -y install software-properties-common >> $LOG_FILE 2>&1
apt-add-repository -y ppa:bitcoin/bitcoin >> $LOG_FILE 2>&1
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
apt-get -y install libevent-dev >> $LOG_FILE 2>&1
apt-get -y install libdb4.8-dev libdb4.8++-dev >> $LOG_FILE 2>&1
apt-get -y install libboost-all-dev >> $LOG_FILE 2>&1

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
	ufw allow 24156/tcp >> $LOG_FILE 2>&1
	ufw allow 24157/tcp >> $LOG_FILE 2>&1
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
listen=1
server=1
daemon=1
maxconnections=24
masternode=1
masternodeprivkey=$key
externalip=$ip
EOF
chown -R $whoami:$whoami /home/$whoami

#Install GoByte Daemon
echo 'Downloading daemon...'
cd
wget https://github.com/gobytecoin/gobyte/releases/download/v0.12.2.3/GoByteCore-0.12.2.3_Linux64.tar.gz >> $LOG_FILE 2>&1
tar xvzf GoByteCore-0.12.2.3_Linux64.tar.gz >> $LOG_FILE 2>&1
cp GoByteCore-0.12.2.3/usr/local/bin/gobyted /usr/bin/ >> $LOG_FILE 2>&1
cp GoByteCore-0.12.2.3/usr/local/bin/gobyte-cli /usr/bin/ >> $LOG_FILE 2>&1
cp GoByteCore-0.12.2.3/usr/local/bin/gobyte-tx /usr/bin/ >> $LOG_FILE 2>&1
rm -rf GoByteCore-0.12.2.3 >> $LOG_FILE 2>&1

#Run gobyted as selected user
sudo -H -u $whoami bash -c 'gobyted' >> $LOG_FILE 2>&1

echo 'GoByte Core prepared and lunched'

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
echo "Now, you need to finally start your masternode in the following order: "
echo "1- Go to your windows/mac wallet and modify masternode.conf as required, then restart and from the Masternode tab"
echo "2- Select the newly created masternode and then click on start-alias."
echo "3- Once completed, please return to VPS and wait for the wallet to be synced."
echo "4- Then you can try the command 'gobyte-cli masternode status' to get the masternode status."

su $whoami
