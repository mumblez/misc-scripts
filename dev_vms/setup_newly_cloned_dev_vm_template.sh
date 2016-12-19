#!/bin/bash
# Script to setup a new user on a new dev-vm after a fresh clone
# of the template.
# Ensure svn account is created first

die() { echo $* 1>&2 ; exit 1 ; }

# settings
FIRSTNAME=$(echo @option.first_name@ | tr '[:upper:]' '[:lower:]')
PRETTY_FNAME="$(tr '[:lower:]' '[:upper:]' <<< ${FIRSTNAME:0:1})${FIRSTNAME:1}"
LASTNAME=$(echo @option.last_name@ | tr '[:upper:]' '[:lower:]')
PRETTY_LNAME="$(tr '[:lower:]' '[:upper:]' <<< ${LASTNAME:0:1})${LASTNAME:1}"
USERNAME="${FIRSTNAME}.${LASTNAME}"
HOSTNAME="dev-${FIRSTNAME:0:1}${LASTNAME}"
# check it also doesn't exist (and maybe setup SVN)
PASSWORD="@option.password@"   # passed from rundeck
OWNIP=$(curl -s -L http://someip:4001/v2/keys/rundeck/jobqueue/@option.parent_exec_id@/ip | jq -r '.node.value')
WORKSTATION_IP="@option.workstation_ip@"        # pass in via RD - too much hassle to pull automatically
TOOLS="chpasswd svn git adduser"
WORKING_DIR=$(mktemp -d /tmp/new_user_setup_XXX)
NEW_DIRS=$(mktemp $WORKING_DIR/new_dirs_XXX.txt)
SYMLINKS_FILE=$(mktemp $WORKING_DIR/symlinks_file_XXX.txt)
SVN_URL="https://someserver/svn/trunk"
DEV_BASE="/home/$USERNAME/dev"
PROJECTS_BASE="$DEV_BASE/projects"
INFRASTRUCTURE_BASE="$DEV_BASE/infrastructure"
GIT_CONFIG="/home/$USERNAME/.gitconfig"
GIT_DEPLOY_KEY="/root/keys/cl_deploy"
GITLAB_API="someapi"
GITLAB_URL="https://someserver"
# RD_JOB_EXECID
# etcd URL
# etcd add / read execid, IP, hostname / username
# delete job / execid folder after setting up the machine

# validation

for TOOL in $TOOLS; do
        which $TOOL >/dev/null 2>&1 || die "ERROR: $TOOL is not installed"
done

# add username to salt grains for easy use afterwards
if grep -q '3b_env: dev' /etc/salt/grains;
then
  echo "3b_developer: $USERNAME" >> /etc/salt/grains
fi

# create new user and set password
#adduser --ingroup dev --force-badname $USERNAME
useradd -g dev -G itadmins $USERNAME -m
echo "$USERNAME:$PASSWORD" | chpasswd

# add easy shortcut to nfs dev_share
#ln -snf /misc/dev_share "/home/$USERNAME/dev_share"


# new directories
cat > "${NEW_DIRS}" <<EOF
/somecomp/lib/shared
/somecomp/lib/php5/offspring
/somecomp/config/common
/somecomp/config/website
/somecomp/config/intranet
/somecomp/config/offspring
/somecomp/secure/website
/somecomp/var/web/data/files.registration
/somecomp/var/web/data/files.hrcv
/somecomp/var/web/data/files.production
/somecomp/var/web/data/files.attachment
/somecomp/var/cache/dwoo/offspring
/somecomp/lib/php5/offspring
/somecomp/lib/js
/somecomp/lib/templates
/somecomp/log/intranet
/somecomp/log/website
/somecomp/www/thirdbridge
EOF

while read line; do
        mkdir -p "$line"
done < "${NEW_DIRS}"


# create standard git directory for future repository store
sudo -u "$USERNAME" mkdir -p "${DEV_BASE}/git_repos"
sudo -u "$USERNAME" echo "Clone your repositories here!" > "${DEV_BASE}/git_repos/README.txt"

# svn pull - account needs to exist on svn to pull automatically
sudo -u "$USERNAME" mkdir -p "$INFRASTRUCTURE_BASE"
sudo -u "$USERNAME" mkdir -p "$PROJECTS_BASE"
sudo -u "$USERNAME" svn checkout --trust-server-cert  --non-interactive --depth empty "${SVN_URL}/projects" "$PROJECTS_BASE" --username "$USERNAME" --password "$PASSWORD"
sudo -u "$USERNAME" svn checkout --trust-server-cert --non-interactive --depth empty "${SVN_URL}/infrastructure" "$INFRASTRUCTURE_BASE"
cd "$PROJECTS_BASE"
echo "INFO: Pulling projects down....."
sudo -u "$USERNAME" svn up intranet website common zaibatsu restserver &>/dev/null
cd "$INFRASTRUCTURE_BASE"
echo "INFO: Pulling infrastructure parts down....."
sudo -u "$USERNAME" svn up php5.2 offspring chrome-plugins base sphinx yii &>/dev/null


# create symlinks
# later on version control file and pull from gitlab
cat > "${SYMLINKS_FILE}" <<EOF
$INFRASTRUCTURE_BASE/base/bin/* /somecomp/bin/
$PROJECTS_BASE/intranet/bin/ /somecomp/bin/intranet
$PROJECTS_BASE/website/bin/ /somecomp/bin/website
$PROJECTS_BASE/common/lib/php/* /somecomp/lib/php5/
$PROJECTS_BASE/common/lib/js/* /somecomp/lib/js/
$PROJECTS_BASE/common/src/phplib/* /somecomp/lib/php5/somecomp/
$PROJECTS_BASE/common/src/css/fck_custom.css /somecomp/lib/css/somecomp/
$PROJECTS_BASE/common/src/js /somecomp/lib/shared/
$PROJECTS_BASE/common/src/css /somecomp/lib/shared/
$PROJECTS_BASE/common/config/dev/offspring /somecomp/config/common/
$PROJECTS_BASE/intranet/config/dev/config.xml /somecomp/config/intranet/
$PROJECTS_BASE/intranet/config/dev/config.inc.php /somecomp/config/intranet/
$PROJECTS_BASE/intranet/config/dev/db.properties /somecomp/config/intranet/
$PROJECTS_BASE/intranet/config/dev/offspring /somecomp/config/intranet/
$PROJECTS_BASE/website/config/dev/config.xml /somecomp/config/website/
$PROJECTS_BASE/website/config/dev/config.inc.php /somecomp/config/website/
$PROJECTS_BASE/website/src/forms /somecomp/config/website/
$PROJECTS_BASE/website/config/dev/offspring /somecomp/config/website/
$PROJECTS_BASE/zaibatsu/config/dev /somecomp/config/zaibatsu
$PROJECTS_BASE/zaibatsu/src/protected /somecomp/lib/php5/projects/zaibatsu
$PROJECTS_BASE/intranet/src/html/ /somecomp/www/intranet
$PROJECTS_BASE/website/src/html/ /somecomp/www/website
$PROJECTS_BASE/zaibatsu/src/html/ /somecomp/www/zaibatsu
$PROJECTS_BASE/restserver/src /somecomp/www/restserver
$PROJECTS_BASE/intranet/src/js /somecomp/www/intranet/
$PROJECTS_BASE/intranet/src/css /somecomp/www/intranet/
$PROJECTS_BASE/website/src/js /somecomp/www/website/
$PROJECTS_BASE/website/src/css /somecomp/www/website/
$PROJECTS_BASE/intranet/resources/img /somecomp/www/intranet/
$PROJECTS_BASE/intranet/resources/fonts /somecomp/www/intranet/
$PROJECTS_BASE/website/resources/img /somecomp/www/website/
$PROJECTS_BASE/website/resources/fonts /somecomp/www/website/
$PROJECTS_BASE/intranet/src/phplib/ /somecomp/lib/php5/somecomp/projects/intranet
$PROJECTS_BASE/website/src/phplib/ /somecomp/lib/php5/somecomp/projects/website
$PROJECTS_BASE/intranet/lib/pear/OLE /somecomp/lib/php5/
$PROJECTS_BASE/intranet/lib/pear/PHPUnit /somecomp/lib/php5/
$PROJECTS_BASE/website/src/htmltemplates/ /somecomp/lib/templates/website
$PROJECTS_BASE/intranet/src/htmltemplates/ /somecomp/lib/templates/intranet
$PROJECTS_BASE/intranet/resources/fonts/ /somecomp/www/intranet/fonts
$PROJECTS_BASE/website/resources/flash/ /somecomp/www/website/
$PROJECTS_BASE/website/lib/ /somecomp/lib/php5/projects/website
$PROJECTS_BASE/website/src/library/dist/scripts /somecomp/www/website/js/v2
$PROJECTS_BASE/website/src/library/dist/css /somecomp/www/website/css/v2
$PROJECTS_BASE/website/src/library/dist/images /somecomp/www/website/img/v2
$PROJECTS_BASE/website/src/library/dist/fonts /somecomp/www/website/fonts/v2
$PROJECTS_BASE/website/src/static/ /somecomp/www/website/static
$PROJECTS_BASE/website/src/static/ /somecomp/www/thirdbridge/static
/somecomp/lib/php5/somecomp/v1_deprecated /somecomp/lib/php5/somecomp
/somecomp/lib/php5/somecomp/v1_deprecated/eventLog /somecomp/lib/php5/somecomp/v1_deprecated/EventLog
/somecomp/lib/php5/somecomp/v1_deprecated/invoice /somecomp/lib/php5/somecomp/v1_deprecated/Invoice
/somecomp/lib/php5/somecomp/v1_deprecated/mail /somecomp/lib/php5/somecomp/v1_deprecated/Mail
/somecomp/lib/php5/Dwoo /somecomp/lib/php5/dwoo/Dwoo
/somecomp/lib/php5/fckeditor/ /somecomp/www/intranet/fckeditor_templates
/somecomp/lib/js/dojo/ /somecomp/www/intranet/js/
$INFRASTRUCTURE_BASE/offspring/src/phplib/offspring-core.php /somecomp/lib/php5/offspring/
$INFRASTRUCTURE_BASE/offspring/src/phplib/packages /somecomp/lib/php5/offspring/
$INFRASTRUCTURE_BASE/offspring/config/dev/offspring-rules.xml /somecomp/config/offspring/
$INFRASTRUCTURE_BASE/php5.2/config/dev/* /somecomp/config/
$INFRASTRUCTURE_BASE/base/config/dev/comm.yml /somecomp/config/
$INFRASTRUCTURE_BASE/base/lib/perl/comm.pm /somecomp/lib/perl/
$INFRASTRUCTURE_BASE/yii/lib/yii /somecomp/lib/php5/
$PROJECTS_BASE/intranet/config/dev/apache/intranet-v2 /etc/apache2/sites-available/intranet
$PROJECTS_BASE/intranet/config/dev/apache/sms-v2 /etc/apache2/sites-available/sms
$PROJECTS_BASE/intranet/config/dev/apache/umg-v2 /etc/apache2/sites-available/umg
$PROJECTS_BASE/website/config/dev/apache/website-v2 /etc/apache2/sites-available/website
$PROJECTS_BASE/website/config/dev/apache/thirdbridge-v2 /etc/apache2/sites-available/thirdbridge
$PROJECTS_BASE/zaibatsu/config/dev/apache/zaibatsu-v2 /etc/apache2/sites-available/zaibatsu
$PROJECTS_BASE/restserver/config/dev/restserver /etc/apache2/sites-available/restserver
$PROJECTS_BASE/intranet/cron/dev/cron /etc/cron.d/intranet
$PROJECTS_BASE/website/config/dev/apache/apache_passwords /somecomp/secure/website/
$PROJECTS_BASE/website/cron/errorcheck /etc/cron.d/website
EOF

[ -h /somecomp/lib/php5/somecomp/projects/intranet/phplib ] && echo "WARNING: Found dodgy link"



while read line; do
        #echo "INFO: Creating symlinks...."
        #echo "INFO: Creating symlink for $line"
        ln -snf $line
        #[ -h /somecomp/lib/php5/somecomp/projects/intranet/phplib ] && echo "WARNING: Found dodgy link"
done < "${SYMLINKS_FILE}"

# Initialise rabbitmq exchange / queue
php /somecomp/bin/intranet/amqpExchangeAndQueueSetup.php -esomecomp -qsymfony --run
# directories to make after symlinking
mkdir -p /somecomp/lib/php5/dwoo/compiled
mkdir -p /somecomp/log/zaibatsu

# permissions
chown $USERNAME:dev -R "$DEV_BASE"
chmod 777 /somecomp/lib/php5/dwoo/compiled
chmod 777 -R /somecomp/var/compiled/
chmod 777 -R /somecomp/var/cache/
chmod 777 -R /somecomp/log/
chmod 777 -R /somecomp/lib/php5/projects/zaibatsu/runtime

# set hostname
# dev-<initial><surname>
# /etc/hostname and hostname <hostname>

echo "$HOSTNAME" > /etc/hostname
hostname "$HOSTNAME"

# setup default gitconfig
cat > ${GIT_CONFIG} <<EOF
[user]
        name = $PRETTY_FNAME $PRETTY_LNAME
        email = ${FIRSTNAME}.${LASTNAME}@somecomp.com

[color]
        ui = true
EOF

chown ${USERNAME} ${GIT_CONFIG}


# Pull down git repos
#echo "INFO: pulling git repositories down"
# use key, pull repo, install composer and run composer install, set permissions, set symlinks

# backup /etc/php52/php.ini before symlinking dev one
cd /etc/php52
if [ -e php.ini ]; then
        cp php.ini php.ini.bak
fi

# symlink dev php.ini (php52)
ln -snf "${INFRASTRUCTURE_BASE}/php5.2/config/dev/php-v2.ini" php.ini
# add new version or a v2 version to svn and symlink to that, add extensions to end of new file

# copy clone and samba conf edit smb.conf
echo "INFO: Updating samba configuration..."
cd /etc/samba
cp smb.conf smb.conf.bak
sed "s/\(hosts allow =\)/\1 $WORKSTATION_IP/" -i smb.conf.clone
sed "s/\(guest account =\)/\1 $USERNAME/" -i smb.conf.clone
sed "s/\(force user =\)/\1 $USERNAME/" -i smb.conf.clone
sed "s/^\(path=\)/\1\/home\/$USERNAME/" -i smb.conf.clone
cp smb.conf.clone smb.conf

# edit php and apache configs
service apache2 stop
service php52-fpm stop
CONFIGS_TO_EDIT="/etc/apache2/envvars \
/usr/local/php52/etc/php-fpm.conf"
for AP_CONFIG in $CONFIGS_TO_EDIT; do
        sed "s/www-data/$USERNAME/" -i "$AP_CONFIG"
done

chown ${USERNAME}:dev /var/lock/apache2/ -R
chown ${USERNAME}:dev /var/www/fastcgi/ -R
chown ${USERNAME}:dev /var/run/apache2/ -R
chown ${USERNAME}:dev /var/lib/apache2/ -R
chown ${USERNAME}:dev /somecomp/log/ -R



# Setup specialist-extranet - in future, when common repo's moved into its own namespace, loop this routine for all repo's in somecomp_web_v2 namespace
#cd /etc/php5/fpm/pool.d
## Setup user as owner, so cache and log access isn't a problem (user pulls files down as themselves)
#sed "s/^user =.*/user = $USERNAME/" -i specialist-extranet.conf


# backup interfaces file before overwriting
echo "INFO: Setting static IP address..."
cp /etc/network/{interfaces,interfaces.bak} || die "ERROR: Failed to backup the network interfaces file"
# set IP
# /etc/network/interfaces, use below as a template and replace fields

cat > /etc/network/interfaces <<EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet static
        address $OWNIP
        gateway somegateway
        netmask 255.255.252.0
        post-up /sbin/ip route add default dev eth0
        # dns-* options are implemented by the resolvconf package, if installed
        dns-nameservers somedns
        dns-search dev.somecomp.com corp.somecomp.com
EOF

#service networking restart # will complain file exists, maybe best to reboot right at the end

# remove apache warning
echo "INFO: Updating vm hosts file"
echo "ServerName $HOSTNAME" >> /etc/apache2/apache2.conf

# hosts file
echo "$OWNIP    $HOSTNAME" >> /etc/hosts
echo "$OWNIP    www.somecomp.com" >> /etc/hosts
echo "$OWNIP    www.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    intranet.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    umg.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    zaibatsu.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    specialist.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    restserver.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    auth.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    externalapi.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    pluginapi.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    intranet-v2.dev.somecomp.com" >> /etc/hosts

# enable sites
echo "INFO: Enabling apache vhosts..."
a2ensite {intranet,sms,umg,website,zaibatsu,restserver}

echo "INFO: Restarting samba and php-fpm"
# [re]start services
/etc/init.d/samba restart
/etc/init.d/apache2 restart
/etc/init.d/php52-fpm restart
#/etc/init.d/php55-fpm restart


# Adding ssh public key(s)
DEV_ID=$(curl --header "PRIVATE-TOKEN: $GITLAB_API" -k -s "${GITLAB_URL}/api/v3/users" | jq --arg dev_user "${FIRSTNAME}.${LASTNAME}" '.[] | select(.username == $dev_user) | .id')
if [ ! -z $DEV_ID ]; then
        curl --header "PRIVATE-TOKEN: $GITLAB_API" -k -s "${GITLAB_URL}/api/v3/users/${DEV_ID}/keys" | jq -r '.[].key' >> "/home/${USERNAME}/.ssh/authorized_keys"
fi

# cleanup
echo "INFO: Cleaning up..."
rm -rf "$WORKING_DIR"

# reboot box - mainly so networking / static IP takes effect
echo
echo "=========================================================================================="
echo "INFO: Rebooting, wait a couple of minutes before connecting to ${USERNAME}@${OWNIP}"
echo "=========================================================================================="
echo
( reboot )
exit 0
