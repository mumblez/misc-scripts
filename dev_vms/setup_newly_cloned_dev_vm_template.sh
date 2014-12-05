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
OWNIP=$(curl -s -L http://***REMOVED***.50:4001/v2/keys/rundeck/jobqueue/@option.parent_exec_id@/ip | jq -r '.node.value')
WORKSTATION_IP="@option.workstation_ip@"        # pass in via RD - too much hassle to pull automatically
TOOLS="chpasswd svn git adduser"
WORKING_DIR=$(mktemp -d /tmp/new_user_setup_XXX)
NEW_DIRS=$(mktemp $WORKING_DIR/new_dirs_XXX.txt)
SYMLINKS_FILE=$(mktemp $WORKING_DIR/symlinks_file_XXX.txt)
SVN_URL="https://***REMOVED***.***REMOVED***.com/svn/trunk"
DEV_BASE="/home/$USERNAME/dev"
PROJECTS_BASE="$DEV_BASE/projects"
INFRASTRUCTURE_BASE="$DEV_BASE/infrastructure"
GIT_CONFIG="/home/$USERNAME/.gitconfig"
GIT_DEPLOY_KEY="/***REMOVED***/keys/cl_deploy"
GITLAB_API="***REMOVED***"
GITLAB_URL="https://***REMOVED***.***REMOVED***.com"
# RD_JOB_EXECID
# etcd URL
# etcd add / read execid, IP, hostname / username
# delete job / execid folder after setting up the machine

# validation

for TOOL in $TOOLS; do
        which $TOOL >/dev/null 2>&1 || die "ERROR: $TOOL is not installed"
done


# create new user and set password
#adduser --ingroup dev --force-badname $USERNAME
useradd -g dev -G itadmins $USERNAME -m
echo "$USERNAME:$PASSWORD" | chpasswd

# add easy shortcut to nfs dev_share
#ln -snf /misc/dev_share "/home/$USERNAME/dev_share"


# new directories
cat > "${NEW_DIRS}" <<EOF
/***REMOVED***/lib/shared
/***REMOVED***/lib/php5/offspring
/***REMOVED***/config/common
/***REMOVED***/config/website
/***REMOVED***/config/intranet
/***REMOVED***/config/offspring
/***REMOVED***/secure/website
/***REMOVED***/var/web/data/files.registration
/***REMOVED***/var/web/data/files.hrcv
/***REMOVED***/var/web/data/files.production
/***REMOVED***/var/web/data/files.attachment
/***REMOVED***/var/cache/dwoo/offspring
/***REMOVED***/lib/php5/offspring
/***REMOVED***/lib/js
/***REMOVED***/lib/templates
/***REMOVED***/log/intranet
/***REMOVED***/log/website
/***REMOVED***/www/***REMOVED***
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
sudo -u "$USERNAME" svn checkout --depth empty "${SVN_URL}/projects" "$PROJECTS_BASE" --username "$USERNAME" --password "$PASSWORD"
sudo -u "$USERNAME" svn checkout --depth empty "${SVN_URL}/infrastructure" "$INFRASTRUCTURE_BASE"
cd "$PROJECTS_BASE"
echo "INFO: Pulling projects down....."
sudo -u "$USERNAME" svn up intranet website common zaibatsu restserver &>/dev/null
cd "$INFRASTRUCTURE_BASE"
echo "INFO: Pulling infrastructure parts down....."
sudo -u "$USERNAME" svn up php5.2 offspring chrome-plugins base sphinx yii &>/dev/null


# create symlinks
# later on version control file and pull from gitlab
cat > "${SYMLINKS_FILE}" <<EOF
$INFRASTRUCTURE_BASE/base/bin/* /***REMOVED***/bin/
$PROJECTS_BASE/intranet/bin/ /***REMOVED***/bin/intranet
$PROJECTS_BASE/website/bin/ /***REMOVED***/bin/website
$PROJECTS_BASE/common/lib/php/* /***REMOVED***/lib/php5/
$PROJECTS_BASE/common/lib/js/* /***REMOVED***/lib/js/
$PROJECTS_BASE/common/src/phplib/* /***REMOVED***/lib/php5/***REMOVED***/
$PROJECTS_BASE/common/src/css/fck_custom.css /***REMOVED***/lib/css/***REMOVED***/
$PROJECTS_BASE/common/src/js /***REMOVED***/lib/shared/
$PROJECTS_BASE/common/src/css /***REMOVED***/lib/shared/
$PROJECTS_BASE/common/config/dev/offspring /***REMOVED***/config/common/
$PROJECTS_BASE/intranet/config/dev/config.xml /***REMOVED***/config/intranet/
$PROJECTS_BASE/intranet/config/dev/config.inc.php /***REMOVED***/config/intranet/
$PROJECTS_BASE/intranet/config/dev/db.properties /***REMOVED***/config/intranet/
$PROJECTS_BASE/intranet/config/dev/offspring /***REMOVED***/config/intranet/
$PROJECTS_BASE/website/config/dev/config.xml /***REMOVED***/config/website/
$PROJECTS_BASE/website/config/dev/config.inc.php /***REMOVED***/config/website/
$PROJECTS_BASE/website/src/forms /***REMOVED***/config/website/
$PROJECTS_BASE/website/config/dev/offspring /***REMOVED***/config/website/
$PROJECTS_BASE/zaibatsu/config/dev /***REMOVED***/config/zaibatsu
$PROJECTS_BASE/zaibatsu/src/protected /***REMOVED***/lib/php5/projects/zaibatsu
$PROJECTS_BASE/intranet/src/html/ /***REMOVED***/www/intranet
$PROJECTS_BASE/website/src/html/ /***REMOVED***/www/website
$PROJECTS_BASE/zaibatsu/src/html/ /***REMOVED***/www/zaibatsu
$PROJECTS_BASE/restserver/src /***REMOVED***/www/restserver
$PROJECTS_BASE/intranet/src/js /***REMOVED***/www/intranet/
$PROJECTS_BASE/intranet/src/css /***REMOVED***/www/intranet/
$PROJECTS_BASE/website/src/js /***REMOVED***/www/website/
$PROJECTS_BASE/website/src/css /***REMOVED***/www/website/
$PROJECTS_BASE/intranet/resources/img /***REMOVED***/www/intranet/
$PROJECTS_BASE/intranet/resources/fonts /***REMOVED***/www/intranet/
$PROJECTS_BASE/website/resources/img /***REMOVED***/www/website/
$PROJECTS_BASE/website/resources/fonts /***REMOVED***/www/website/
$PROJECTS_BASE/intranet/src/phplib/ /***REMOVED***/lib/php5/***REMOVED***/projects/intranet
$PROJECTS_BASE/website/src/phplib/ /***REMOVED***/lib/php5/***REMOVED***/projects/website
$PROJECTS_BASE/intranet/lib/pear/OLE /***REMOVED***/lib/php5/
$PROJECTS_BASE/intranet/lib/pear/PHPUnit /***REMOVED***/lib/php5/
$PROJECTS_BASE/website/src/htmltemplates/ /***REMOVED***/lib/templates/website
$PROJECTS_BASE/intranet/src/htmltemplates/ /***REMOVED***/lib/templates/intranet
$PROJECTS_BASE/intranet/resources/fonts/ /***REMOVED***/www/intranet/fonts
$PROJECTS_BASE/website/resources/flash/ /***REMOVED***/www/website/
$PROJECTS_BASE/website/lib/ /***REMOVED***/lib/php5/projects/website
$PROJECTS_BASE/website/src/library/dist/scripts /***REMOVED***/www/website/js/v2
$PROJECTS_BASE/website/src/library/dist/css /***REMOVED***/www/website/css/v2
$PROJECTS_BASE/website/src/library/dist/images /***REMOVED***/www/website/img/v2
$PROJECTS_BASE/website/src/library/dist/fonts /***REMOVED***/www/website/fonts/v2
$PROJECTS_BASE/website/src/static/ /***REMOVED***/www/website/static
/***REMOVED***/lib/php5/***REMOVED***/v1_deprecated /***REMOVED***/lib/php5/Cognolink
/***REMOVED***/lib/php5/***REMOVED***/v1_deprecated/eventLog /***REMOVED***/lib/php5/***REMOVED***/v1_deprecated/EventLog
/***REMOVED***/lib/php5/***REMOVED***/v1_deprecated/invoice /***REMOVED***/lib/php5/***REMOVED***/v1_deprecated/Invoice
/***REMOVED***/lib/php5/***REMOVED***/v1_deprecated/mail /***REMOVED***/lib/php5/***REMOVED***/v1_deprecated/Mail
/***REMOVED***/lib/php5/Dwoo /***REMOVED***/lib/php5/dwoo/Dwoo
/***REMOVED***/lib/php5/fckeditor/ /***REMOVED***/www/intranet/fckeditor_templates
/***REMOVED***/lib/js/dojo/ /***REMOVED***/www/intranet/js/
$INFRASTRUCTURE_BASE/offspring/src/phplib/offspring-core.php /***REMOVED***/lib/php5/offspring/
$INFRASTRUCTURE_BASE/offspring/src/phplib/packages /***REMOVED***/lib/php5/offspring/
$INFRASTRUCTURE_BASE/offspring/config/dev/offspring-rules.xml /***REMOVED***/config/offspring/
$INFRASTRUCTURE_BASE/php5.2/config/dev/* /***REMOVED***/config/
$INFRASTRUCTURE_BASE/base/config/dev/comm.yml /***REMOVED***/config/
$INFRASTRUCTURE_BASE/base/lib/perl/comm.pm /***REMOVED***/lib/perl/
$INFRASTRUCTURE_BASE/yii/lib/yii /***REMOVED***/lib/php5/
$PROJECTS_BASE/intranet/config/dev/apache/intranet-v2 /etc/apache2/sites-available/intranet
$PROJECTS_BASE/intranet/config/dev/apache/sms-v2 /etc/apache2/sites-available/sms
$PROJECTS_BASE/intranet/config/dev/apache/umg-v2 /etc/apache2/sites-available/umg
$PROJECTS_BASE/website/config/dev/apache/website-v2 /etc/apache2/sites-available/website
$PROJECTS_BASE/website/config/dev/apache/***REMOVED***-v2 /etc/apache2/sites-available/***REMOVED***
$PROJECTS_BASE/zaibatsu/config/dev/apache/zaibatsu-v2 /etc/apache2/sites-available/zaibatsu
$PROJECTS_BASE/restserver/config/dev/restserver /etc/apache2/sites-available/restserver
$PROJECTS_BASE/intranet/cron/dev/cron /etc/cron.d/intranet
$PROJECTS_BASE/website/config/dev/apache/apache_passwords /***REMOVED***/secure/website/
$PROJECTS_BASE/website/cron/errorcheck /etc/cron.d/website
EOF

[ -h /***REMOVED***/lib/php5/***REMOVED***/projects/intranet/phplib ] && echo "WARNING: Found dodgy link" 

while read line; do
        #echo "INFO: Creating symlinks...."
        #echo "INFO: Creating symlink for $line"
        ln -snf $line
        #[ -h /***REMOVED***/lib/php5/***REMOVED***/projects/intranet/phplib ] && echo "WARNING: Found dodgy link" 
done < "${SYMLINKS_FILE}"

# directories to make after symlinking
mkdir -p /***REMOVED***/lib/php5/dwoo/compiled
mkdir -p /***REMOVED***/log/zaibatsu

# permissions
chown $USERNAME:dev -R "$DEV_BASE"
chmod 777 /***REMOVED***/lib/php5/dwoo/compiled
chmod 777 -R /***REMOVED***/var/compiled/
chmod 777 -R /***REMOVED***/var/cache/
chmod 777 -R /***REMOVED***/log/
chmod 777 -R /***REMOVED***/lib/php5/projects/zaibatsu/runtime

# set hostname
# dev-<initial><surname>
# /etc/hostname and hostname <hostname>

echo "$HOSTNAME" > /etc/hostname
hostname "$HOSTNAME"

# setup default gitconfig
cat > ${GIT_CONFIG} <<EOF
[user]
        name = $PRETTY_FNAME $PRETTY_LNAME
        email = ${FIRSTNAME}.${LASTNAME}@***REMOVED***.com

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
chown ${USERNAME}:dev /var/www/fast***REMOVED***i/ -R
chown ${USERNAME}:dev /var/run/apache2/ -R
chown ${USERNAME}:dev /var/lib/apache2/ -R
chown ${USERNAME}:dev /***REMOVED***/log/ -R



# Setup specialist-extranet - in future, when common repo's moved into its own namespace, loop this routine for all repo's in ***REMOVED***_web_v2 namespace
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
        gateway ***REMOVED***.1
        netmask 255.255.252.0
        post-up /sbin/ip route add default dev eth0
        # dns-* options are implemented by the resolvconf package, if installed
        dns-nameservers ***REMOVED***.11
        dns-search dev.***REMOVED***.com corp.***REMOVED***.com
EOF

#service networking restart # will complain file exists, maybe best to reboot right at the end

# remove apache warning
echo "INFO: Updating vm hosts file"
echo "ServerName $HOSTNAME" >> /etc/apache2/apache2.conf

# hosts file
echo "$OWNIP    $HOSTNAME" >> /etc/hosts
echo "$OWNIP    www.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    www.dev.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    intranet.dev.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    umg.dev.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    zaibatsu.dev.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    specialist.dev.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    restserver.dev.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    auth.dev.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    externalapi.dev.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    pluginapi.dev.***REMOVED***.com" >> /etc/hosts
echo "$OWNIP    intranet-v2.dev.***REMOVED***.com" >> /etc/hosts

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
