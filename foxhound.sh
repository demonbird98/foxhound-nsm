if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit 1
fi

echo "Please enter your Critical Stack API Key: "
read api
echo "Please enter your SMTP server"
read smtp_server
echo "Please enter your SMTP user"
read smtp_user
echo "Please enter your SMTP password"
read smtp_pass
echo "Please enter your notification email"
read notification

echo "Check security patches"
apt-get update
apt-get -y upgrade

$INSTALL_DIR = /nsm/  
mkdir -p $INSTALL_DIR
mkdir -p $INSTALL_DIR/pcap/
mkdir -p $INSTALL_DIR/scripts/
mkdir -p $INSTALL_DIR/bro/
mkdir -p $INSTALL_DIR/bro/extracted/

echo "Installing GEO-IP"
install_geoip () {
#	wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
#	wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCityv6-beta/GeoLiteCityv6.dat.gz
#	gunzip GeoLiteCity.dat.gz
#	gunzip GeoLiteCityv6.dat.gz
#	mv GeoLiteCity* /usr/share/GeoIP/
#	ln -s /usr/share/GeoIP/GeoLiteCity.dat /usr/share/GeoIP/GeoIPCity.dat
#	ln -s /usr/share/GeoIP/GeoLiteCityv6.dat /usr/share/GeoIP/GeoIPCityv6.dat
}

install_packages () {
	echo "Installing Required RPMs"
	sudo apt-get -y install cmake make gcc g++ flex bison libpcap-dev libssl-dev python-dev swig zlib1g-dev ssmtp htop vim libgeoip-dev ethtool git tshark tcpdump nmap mailutils nc 
}


config_net_ipv6 () {
#	echo "Disabling IPv6"
#	echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
#	sed -i '1 s/$/ ipv6.disable=1/' /boot/cmdline.txt
#	sysctl -p
}

config_net_opts () {
#	echo "Configuring network options"
#	echo "
#		#!/bin/bash
#		for i in rx tx gso gro; do ethtool -K eth0 $i off; done;
#		ifconfig eth0 promisc
#		ifconfig eth0 mtu 9000
#		exit 0
#	" \ >  /etc/network/if-up.d/interface-tuneup
#	chmod +x /etc/network/if-up.d/interface-tuneup
#	ifconfig eth0 down && ifconfig eth0 up
}

install_netsniff () {
#	echo "Installing Netsniff-NG PCAP"
#	touch /etc/sysconfig/netsniff-ng
#	git clone https://github.com/netsniff-ng/netsniff-ng.git
#	cd netsniff-ng
#	./configure && make && make install
}

create_service_netsniff () {
	echo "Creating Netsniff-NG service"
		echo "[Unit]
		Description=Netsniff-NG PCAP
		After=network.target

		[Service]
		ExecStart=/usr/local/sbin/netsniff-ng --in eth0 --out $INSTALL_DIR/pcap/ --bind-cpu 3 -s --interval 100MiB --prefix=foxhound-
		Type=simple
		EnvironmentFile=-/etc/sysconfig/netsniff-ng

		[Install]
		WantedBy=multi-user.target" > /etc/systemd/system/netsniff-ng.service
	systemctl enable netsniff-ng
	systemctl daemon-reload
	service netsniff-ng start
}

config_ssmtp () {
	echo "Configuring SSMTP"
		echo "
		root=$cs_notification
		mailhub=$cs_smtp_server
		hostname=foxhound
		FromLineOverride=YES
		UseTLS=YES
		UseSTARTTLS=YES
		AuthUser=$cs_smtp_user
		AuthPass=$cs_smtp_pass" \ > /etc/ssmtp/ssmtp.conf
}
#ALERT TEMPLATE
echo "#!/bin/sh
{
    echo To: $cs_notification
    echo "Mime-Version: 1.0"
	echo "Content-type: text/html; charset=”iso-8859-1”"
    echo From: bro@foxhound-nsm
    echo Subject: Critical Stack Updated
    echo
    sudo -u critical-stack critical-stack-intel list
} | ssmtp $cs_notification " > /opt/email_alert.sh
chmod +x /opt/email_alert.sh

install_loki () {
	echo "Installing YARA packages"
	apt-get -y install pip gcc python-dev python-pip autoconf libtool
	echo "Installing Pylzma"
		cd /opt/
		wget https://pypi.python.org/packages/fe/33/9fa773d6f2f11d95f24e590190220e23badfea3725ed71d78908fbfd4a14/pylzma-0.4.8.tar.gz
		tar -zxvf pylzma-0.4.8.tar.gz
		cd pylzma-0.4.8/
		python ez_setup.py
		python setup.py
	echo "Installing YARA"
		cd /opt/
		git clone https://github.com/VirusTotal/yara.git
		cd /opt/yara
		./bootstrap.sh
		./configure
		make && make install
	echo "Installing PIP LOKI Packages"
		pip install psutil
		pip install yara-python
		pip install git
		pip install gitpython
		pip install pylzma
		pip install netaddr
	echo "Installing LOKI"
		cd $INSTALL_DIR
		git clone https://github.com/Neo23x0/Loki.git
		cd $INSTALL_DIR/Loki
		git clone https://github.com/Neo23x0/signature-base.git
		chmod +x $INSTALL_DIR/Loki/loki.py
}

install_bro () {
	echo "Installing Bro"
		wget https://www.bro.org/downloads/release/bro-2.4.1.tar.gz
		tar -xzf bro-2.4.1.tar.gz
	cd bro-2.4.1 
		./configure --prefix=/nsm/bro --localstatedir=$INSTALL_DIR/bro/
		make -j 4
		make install
	echo "Setting Bro variables"
	echo "export PATH=/usr/local/bro/bin:\$PATH" >> /etc/profile
}

install_criticalstack () {
	echo "Installing Critical Stack Agent"
		wget http://intel.criticalstack.com/client/critical-stack-intel-arm.deb
		dpkg -i critical-stack-intel-arm.deb
		su -u critical-stack critical-stack-intel api $cs_api 
		rm critical-stack-intel-arm.deb
		su -u critical-stack critical-stack-intel list
		su -u critical-stack critical-stack-intel pull
		#Deploy and start BroIDS
		export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/bro/bin:\$PATH"
	echo "Deploying and starting BroIDS"
		broctl check
		broctl deploy
		broctl cron enable
		#Create update script
	echo "
		sudo -u critical-stack critical-stack-intel config
		echo \"#### Pulling feed update ####\"
		sudo -u critical-stack critical-stack-intel pull
		echo \"#### Applying the updates to the bro config ####\"
		broctl check
		broctl install
		echo \"#### Restarting bro ####\"
		broctl restart
	" \ > $INSTALL_DIR/scripts/criticalstack_update
		sudo chmod +x $INSTALL_DIR/scripts/criticalstack_update
}

install_bro_reporting () {
	#BRO REPORTING
	#PYSUBNETREE
	cd /opt/
	git clone git://git.bro-ids.org/pysubnettree.git
	cd pysubnettree/
	python setup.py install
	#IPSUMDUMP
	cd /opt/
	wget http://www.read.seas.harvard.edu/~kohler/ipsumdump/ipsumdump-1.85.tar.gz
	tar -zxvf ipsumdump-1.85.tar.gz
	cd ipsumdump-1.85/
	./configure && make && make install
}

config_bro_scripts () {
	#PULL BRO SCRIPTS
	cd /usr/local/bro/share/bro/site/
	git clone https://github.com/sneakymonk3y/bro-scripts.git
	echo "@load bro-scripts/geoip"  >> /usr/local/bro/share/bro/site/local.bro
	echo "@load bro-scripts/extact"  >> /usr/local/bro/share/bro/site/local.bro

	if broctl check | grep -q ' ok'; then
	  broctl status
	else echo "bro-script check failed"
	fi
	broctl deploy
}

install_geoip
install_packages
config_net_ipv6
config_net_opts
install_netsniff
create_service_netsniff
config_ssmtp
install_loki
install_bro
install_criticalstack
install_bro_reporting
config_bro_scripts

#CRON JOBS
echo "0-59/5 * * * * root /usr/local/bro/bin/broctl cron" >> /etc/crontab
echo "00 7/19 * * *  root sh $INSTALL_DIR/scripts/criticalstack_update" >> /etc/crontab
echo "0-59/5 * * * * root sh $INSTALL_DIR/Loki/loki.py -p /opt/bro/extracted/ --noprocscan --printAll --dontwait " >> /etc/crontab 

echo "
    ______           __  __                      __
   / ____/___  _  __/ / / /___  __  ______  ____/ /
  / /_  / __ \| |/_/ /_/ / __ \/ / / / __ \/ __  / 
 / __/ / /_/ />  </ __  / /_/ / /_/ / / / / /_/ /  
/_/    \____/_/|_/_/ /_/\____/\__,_/_/ /_/\__,_/   
-  B     L     A     C     K     B     O     X  -

" \ > /etc/motd                                                                 
echo "foxhound" > /etc/hostname



