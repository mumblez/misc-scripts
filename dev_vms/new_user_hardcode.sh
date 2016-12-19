#!/bin/bash
# Script to setup a new user on a new dev-vm after a fresh clone
# of the template.
# Ensure svn account is created first

die() { echo $* 1>&2 ; exit 1 ; }

# settings
USERNAME="robin.hood"		# passed from rundeck - create rd.json to use this value to work out other values and to
# check it also doesn't exist (and maybe setup SVN)
PASSWORD="somecomp"   # passed from rundeck
OWNIP="someip"	    # run ip_search_add.py and use SUCCESSFUL output - rundeck options file (relying on value or user name)
HOSTNAME="dev-rhood"   # passed from rundeck
WORKSTATION_IP="someip"		# to put into samba hosts allow list
TOOLS="chpasswd svn git adduser"
WORKING_DIR=$(mktemp -d /tmp/new_user_setup_XXX)
NEW_DIRS=$(mktemp $WORKING_DIR/new_dirs_XXX.txt)
SYMLINKS_FILE=$(mktemp $WORKING_DIR/symlinks_file_XXX.txt)
SVN_URL="https://someserver.somecomp.com/svn/trunk"
DEV_BASE="/home/$USERNAME/dev"
PROJECTS_BASE="$DEV_BASE/projects"
INFRASTRUCTURE_BASE="$DEV_BASE/infrastructure"


# validation

for TOOL in $TOOLS; do
	which chpasswd >/dev/null 2>&1 || die "ERROR: $TOOL is not installed"
done


# create new user and set password
#adduser --ingroup dev --force-badname --disabled-password $USERNAME
useradd -g dev -G itadmins $USERNAME -m
echo "$USERNAME:$PASSWORD" | chpasswd

# add easy shortcut to nfs dev_share
ln -snf /misc/dev_share "/home/$USERNAME/dev_share"

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
sudo -u "$USERNAME" "${DEV_BASE}/git_repos"
sudo -u "$USERNAME" echo "Clone your repositories here!" > "${DEV_BASE}/git_repos/README.txt"

# svn pull - account needs to exist on svn to pull automatically
sudo -u "$USERNAME" mkdir -p "$INFRASTRUCTURE_BASE"
sudo -u "$USERNAME" mkdir -p "$PROJECTS_BASE"
sudo -u "$USERNAME" svn checkout --depth empty "${SVN_URL}/projects" "$PROJECTS_BASE" --username "$USERNAME" --password "$PASSWORD"
sudo -u "$USERNAME" svn checkout --depth empty "${SVN_URL}/infrastructure" "$INFRASTRUCTURE_BASE"
cd "$PROJECTS_BASE"
sudo -u "$USERNAME" svn up intranet website common zaibatsu
cd "$INFRASTRUCTURE_BASE"
sudo -u "$USERNAME" svn up php5.2 offspring chrome-plugins base sphinx


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
$PROJECTS_BASE/website/config/dev/forms /somecomp/config/website/
$PROJECTS_BASE/website/config/dev/offspring /somecomp/config/website/
$PROJECTS_BASE/intranet/src/html/ /somecomp/www/intranet
$PROJECTS_BASE/website/src/html/ /somecomp/www/website
$PROJECTS_BASE/zaibatsu/src/html/ /somecomp/www/zaibatsu
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
$PROJECTS_BASE/intranet/src/phplib/ /somecomp/lib/php5/somecomp/projects/intranet
$PROJECTS_BASE/website/src/phplib/ /somecomp/lib/php5/somecomp/projects/website
$PROJECTS_BASE/intranet/lib/pear/OLE /somecomp/lib/php5/
$PROJECTS_BASE/intranet/lib/pear/PHPUnit /somecomp/lib/php5/
$PROJECTS_BASE/website/src/htmltemplates/ /somecomp/lib/templates/website
$PROJECTS_BASE/website/resources/flash/ /somecomp/www/website/
$PROJECTS_BASE/website/lib/ /somecomp/lib/php5/projects/website
$PROJECTS_BASE/website/src/library/dist/scripts /somecomp/www/website/js/v2
$PROJECTS_BASE/website/src/library/dist/css /somecomp/www/website/css/v2
$PROJECTS_BASE/website/src/library/dist/images /somecomp/www/website/img/v2
$PROJECTS_BASE/website/src/library/dist/fonts /somecomp/www/website/fonts/v2
$PROJECTS_BASE/website/src/static/ /somecomp/www/website/static
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
$PROJECTS_BASE/intranet/config/dev/apache/intranet-v2 /etc/apache2/sites-available/intranet-v2
$PROJECTS_BASE/intranet/config/dev/apache/sms /etc/apache2/sites-available/sms-v2
$PROJECTS_BASE/intranet/config/dev/apache/umg /etc/apache2/sites-available/umg-v2
$PROJECTS_BASE/website/config/dev/apache/website-v2 /etc/apache2/sites-available/website-v2
$PROJECTS_BASE/website/config/dev/apache/thirdbridge /etc/apache2/sites-available/thirdbridge-v2
$PROJECTS_BASE/zaibatsu/config/dev/apache/zaibatsu /etc/apache2/sites-available/zaibatsu-v2
$PROJECTS_BASE/intranet/cron/dev/cron /etc/cron.d/intranet
$PROJECTS_BASE/website/config/dev/apache/apache_passwords /somecomp/secure/website/
$PROJECTS_BASE/website/cron/errorcheck /etc/cron.d/website
EOF

while read line; do
	ln -sf $line
done < "${SYMLINKS_FILE}"

# directories to make after symlinking
mkdir -p /somecomp/lib/php5/dwoo/compiled
mkdir -p /somecomp/log/zaibatsu

# permissions
chown $USERNAME:dev -R "$DEV_BASE"
chmod 777 /somecomp/lib/php5/dwoo/compiled
chmod 777 -R /somecomp/var/compiled/
chmod 777 -R /somecomp/var/cache/
chmod 777 -R /somecomp/log/

# set hostname
# dev-<initial><surname>
# /etc/hostname and hostname <hostname>

echo "$HOSTNAME" > /etc/hostname
hostname "$HOSTNAME"

# backup /etc/php52/php.ini before symlinking dev one
cd /etc/php52
if [ -e php.ini ]; then
	cp php.ini php.ini.bak
fi

# symlink dev php.ini (php52)
ln -snf "${INFRASTRUCTURE_BASE}/php5.2/config/dev/php-v2.ini" php.ini
# add new version or a v2 version to svn and symlink to that, add extensions to end of new file

# copy clone and samba conf edit smb.conf
cd /etc/samba
cp smb.conf smb.conf.bak
sed "s/\(hosts allow =\)/\1 $WORKSTATION_IP/" -i smb.conf.clone
sed "s/\(guest account =\)/\1 $USERNAME/" -i smb.conf.clone
sed "s/^\(path=\)/\1\/home\/$USERNAME/" -i smb.conf.clone
cp smb.conf.clone smb.conf

# samba
# edit "hosts allow = <IP>" line or just set to 10.10.200.0/24
# edit "guest account = $USERNAME"
# edit "path=/home/$USERNAME"


# backup interfaces file before overwriting
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
        gateway 10.10.100.1
        netmask 255.255.252.0
        post-up /sbin/ip route add default dev eth0
        # dns-* options are implemented by the resolvconf package, if installed
        dns-nameservers 10.10.200.11
        dns-search dev.somecomp.com corp.somecomp.com
EOF

#service networking restart # will complain file exists, maybe best to reboot right at the end

# nic


# hosts file
echo "$OWNIP    $HOSTNAME" >> /etc/hosts
echo "$OWNIP    www.somecomp.com" >> /etc/hosts
echo "$OWNIP    www.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    intranet.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    umg.dev.somecomp.com" >> /etc/hosts
echo "$OWNIP    zaibatsu.dev.somecomp.com" >> /etc/hosts

# enable sites
a2ensite {intranet,sms,umg,website,zaibatsu,symfony-example}


# [re]start services
/etc/init.d/samba restart
/etc/init.d/apache2 restart
/etc/init.d/php52-fpm restart
/etc/init.d/php55-fpm restart

# cleanup
rm -rf "$WORKING_DIR"

# reboot box - mainly so networking / static IP takes effect
reboot
exit 0
