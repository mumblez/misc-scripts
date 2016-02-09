#!/bin/bash

# after upgrade, finish off upgrades, turn on services, setup php(5.2 and 5.5), restore backups

apt-get update && apt-get upgrade -y

# enable ntp and synchronise time
apt-get install ntp
update-rc.d ntp enable
service ntp stop
ntpdate 0.debian.pool.ntp.org
service ntp start
service ntp restart

# stop other services to help with upgrades
service acpid start
update-rc.d memcached enable
service memcached start
apt-get autoremove

update-rc.d -f phpfpm remove
update-rc.d -f phpfpm disable
rm -f /etc/init.d/phpfpm

# restore original web files back (files get missing after uninstalling ***REMOVED***-* packages)
#cp -arf /misc/***REMOVED***_bak/***REMOVED***_qa/. /***REMOVED***

# restore apache vhosts
cp -rf qa_vhost_confs/. /etc/apache2/sites-available
for vhost in `ls qa_vhost_confs`; do ln -sf /etc/apache2/sites-available/$vhost /etc/apache2/sites-enabled/$vhost; done

# setup symfony
mkdir /***REMOVED***/log/symfony

# install apache worker (will uninstall prefork (threaded))
apt-get install apache2-mpm-worker -y

# install php 5.5 (from dotdeb)
apt-get -o Dpkg::Options::="--force-confnew" install php5 -y 
apt-get install php5-{cli,common,curl,dev,gd,imap,mcrypt,memcache,mysql,xsl,fpm} -y

# install php 5.2 (our custom compiled package)
dpkg -i ***REMOVED***-php5.2_5.2.17-2_amd64.deb

# Install apache mod_macro
apt-get install libapache2-mod-macro -y

# setup our directories for easy access
ln -s /usr/local/php52/etc /etc/php52
mkdir /usr/local/php52/logs
touch /usr/local/php52/logs/php-fpm.log
ln -s /usr/local/php52/logs /var/log/php52
mkdir /var/www/fast***REMOVED***i
chown www-data:www-data /var/www/fast***REMOVED***i

# copy our custom configs
cp php.ini /etc/php52
cp php-fpm.conf /etc/php52
cp php52-fpm /etc/init.d/
# install our php52-fpm service
insserv php52-fpm
update-rc.d php52-fpm enable
cp php52macro.conf /etc/apache2/conf.d/
cp php55macro.conf /etc/apache2/conf.d/
cp -f php55-fpm/php-fpm.conf /etc/php5/fpm
cp -rf php55-fpm/pool.d /etc/php5/fpm
rm -f /etc/php5/fpm/pool.d/www.conf

# ensure we disable php55 and fast***REMOVED***i globally and enable macros and actions
a2dismod php5 fast***REMOVED***i
a2enmod macro actions

# load just the libraries (excluding confs) for fast***REMOVED***i
cat /etc/apache2/mods-available/fast***REMOVED***i.load >> /etc/apache2/httpd.conf
#cat /etc/apache2/mods-available/php5.load >> /etc/apache2/httpd.conf
cd /usr/local/php52/bin
for i in fileinfo memcache apc; do yes '' | ./pecl install -f $i; done
VHOSTDIR=/etc/apache2/sites-enabled
for project in `ls $VHOSTDIR`; do sed -i "5i Use php52 $project" $VHOSTDIR/$project; done
service php5-fpm restart && service php52-fpm restart && service apache2 restart
service memcached start

echo "AMEND VHOST IPS for website and intranet!!!"
echo "intranet = <VirtualHost ***REMOVED***:443>"
echo "website = <VirtualHost ***REMOVED***:443>"
echo "intranet = TEST <VirtualHost ***REMOVED***:443>"
echo "website = TEST <VirtualHost ***REMOVED***:443>"
