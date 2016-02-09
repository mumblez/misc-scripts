#!/bin/bash

FILES="/etc/apache2/ /etc/crontab /etc/cron.d/ /etc/sudoers /etc/apt/sources.list.d"

cd /home/***REMOVED***
mkdir backupConfs
cd backupConfs

for i in $FILES; do
  cp -arf $i .
done

#cp -arf /srv/***REMOVED***/ /srv/***REMOVED***.bak

/etc/init.d/acpid stop
apt-get remove --purge ***REMOVED***-{common,intranet,offspring,php5.2,website,zaibatsu} -y
apt-get remove --purge libapache2-mod-php5 php-pear php5 php5-{apc,cli,common,curl,dev,gd,imap,mcrypt,memcache,mysql,xsl} -y
apt-get update && apt-get upgrade -y

cd /etc/apt/sources.list.d
sed -e 's/squeeze/wheezy/g' -e 's/php54/php55/g' -i dotdeb.list
sed -e 's/squeeze/wheezy/g' -e 's/php54/php55/g' -i squeeze.list
cp squeeze.list squeeze.list.bak
mv squeeze.list wheezy.list
sed 's/\smain$/ main contrib non-free/g' -i wheezy.list
mv ***REMOVED***.list ***REMOVED***.list.bak
echo "deb http://packages.corp.***REMOVED***.com/ prod main" > ***REMOVED***.list
apt-get update && apt-get upgrade -y
apt-get dist-upgrade --force-yes
