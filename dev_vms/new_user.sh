#!/bin/bash
# Script to setup a new user on a new dev-vm after a fresh clone
# of the template.
# Ensure svn account is created first

die() { echo $* 1>&2 ; exit 1 ; }

# settings
USER=		# passed from rundeck - create rd.json to use this value to work out other values and to
# check it also doesn't exist (and maybe setup SVN)
PASSWORD=   # passed from rundeck
OWNIP=	    # run ip_search_add.py and use SUCCESSFUL output - rundeck options file (relying on value or user name)
HOSTNAME=   # passed from rundeck
WORKSTATION_IP=		# to put into samba hosts allow list
TOOLS="chpasswd svn git adduser"
WORKING_DIR=$(mktemp -d /tmp/new_user_setup_XXX)
NEW_DIRS=$(mktemp $WORKING_DIR/new_dirs_XXX.txt)
SYMLINKS_FILE=$(mktemp $WORKING_DIR/symlinks_file_XXX.txt)
SVN_URL="https://***REMOVED***.***REMOVED***.com/svn/trunk"
DEV_BASE="/home/$USER/dev"
PROJECTS_BASE="$DEV_BASE/projects"
INFRASTRUCTURE_BASE="$DEV_BASE/infrastructure"


# validation

for TOOL in $TOOLS; do
	which chpasswd >/dev/null 2>&1 || die "ERROR: $TOOL is not installed"
done


# create new user and set password
#adduser --ingroup dev --force-badname $USER
useradd -g dev $USER
echo "$USER:$PASSWORD" | chpasswd

# new directories
cat > "${NEW_DIRS}" <<EOF
/***REMOVED***/lib/shared
/***REMOVED***/lib/php5/offspring
/***REMOVED***/config/common
/***REMOVED***/config/website
/***REMOVED***/config/intranet
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
EOF

while read line; do
	mkdir -p "$line"
done < "${NEW_DIRS}"


# svn pull - account needs to exist on svn to pull automatically
sudo -u "$USER" mkdir -p $DEV_BASE/dev/infrastructure
sudo -u "$USER" mkdir -p $DEV_BASE/dev/projects
sudo -u "$USER" svn checkout --depth empty "${SVN_URL}/projects" $DEV_BASE/projects --username "$USER" --password "$PASSWORD"
sudo -u "$USER" svn checkout "${SVN_URL}/infrastructure" $DEV_BASE/infrastructure
cd /home/"$USER"/dev/projects
sudo -u "$USER" svn up intranet website common


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
$PROJECTS_BASE/website/config/dev/forms /***REMOVED***/config/website/
$PROJECTS_BASE/website/config/dev/offspring /***REMOVED***/config/website/
$PROJECTS_BASE/intranet/src/html/ /***REMOVED***/www/intranet
$PROJECTS_BASE/website/src/html/ /***REMOVED***/www/website
$PROJECTS_BASE/zaibatsu/src/html/ /***REMOVED***/www/zaibatsu
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
$PROJECTS_BASE/intranet/src/phplib/ /***REMOVED***/lib/php5/***REMOVED***/projects/intranet
$PROJECTS_BASE/website/src/phplib/ /***REMOVED***/lib/php5/***REMOVED***/projects/website
$PROJECTS_BASE/intranet/lib/pear/OLE /***REMOVED***/lib/php5/
$PROJECTS_BASE/intranet/lib/pear/PHPUnit /***REMOVED***/lib/php5/
$PROJECTS_BASE/website/src/htmltemplates/ /***REMOVED***/lib/templates/website
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
$PROJECTS_BASE/intranet/config/dev/apache/intranet /etc/apache2/sites-available/
$PROJECTS_BASE/intranet/config/dev/apache/sms /etc/apache2/sites-available/
$PROJECTS_BASE/intranet/config/dev/apache/umg /etc/apache2/sites-available/
$PROJECTS_BASE/intranet/config/dev/apache/website /etc/apache2/sites-available/
$PROJECTS_BASE/intranet/config/dev/apache/***REMOVED*** /etc/apache2/sites-available/
$PROJECTS_BASE/intranet/config/dev/apache/zaibatsu /etc/apache2/sites-available/
$PROJECTS_BASE/intranet/cron/dev/cron /etc/cron.d/intranet
$PROJECTS_BASE/website/config/dev/apache/apache_passwords /***REMOVED***/secure/website/
$PROJECTS_BASE/website/cron/errorcheck /etc/cron.d/website
EOF

while read line; do
	ln -sf $line
done < "${SYMLINKS_FILE}"

mkdir -p /***REMOVED***/lib/php5/dwoo/compiled

# permissions
chown $USER:dev -R "$DEV_BASE"
chmod 777 /***REMOVED***/lib/php5/dwoo/compiled
chmod 777 -R /***REMOVED***/var/compiled/
chmod 777 -R /***REMOVED***/var/cache/
chmod 777 -R /***REMOVED***/log/

# set hostname
# dev-<initial><surname>
# /etc/hostname and hostname <hostname>

# backup /etc/php52/php.ini before symlinking dev one
cd /etc/php52
if [ -e php.ini ]; then
	cp php.ini php.ini.bak
fi

# symlink dev php.ini (php52)
ln -snf "${INFRASTRUCTURE_BASE}/php5.2/config/dev/php.ini" php.ini
# add new version or a v2 version to svn and symlink to that, add extensions to end of new file

# copy clone and samba conf edit smb.conf
cd /etc/samba
cp smb.conf smb.conf.bak
sed -n "s/\(hosts allow =\)/\1 $WORKSTATION_IP/p" smb.conf.clone
sed -n "s/\(guest account =\)/\1 $USER/p" smb.conf.clone
sed -n "s/^\(path=\)/\1\/home\/$USER/p" smb.conf.clone

# samba
# edit "hosts allow = <IP>" line or just set to ***REMOVED***.0/24
# edit "guest account = $USER"
# edit "path=/home/$USER"


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
        gateway ***REMOVED***.1
        netmask 255.255.252.0
        post-up /sbin/ip route add default dev eth0
        # dns-* options are implemented by the resolvconf package, if installed
        dns-nameservers ***REMOVED***.11
        dns-search dev.***REMOVED***.com corp.***REMOVED***.com
EOF

#service networking restart # will complain file exists, maybe best to reboot right at the end

# nic


# hosts file
echo "$OWNIP    $HOSTNAME >> /etc/hosts"
echo "$OWNIP    www.***REMOVED***.com >> /etc/hosts"
echo "$OWNIP    www.dev.***REMOVED***.com >> /etc/hosts"
echo "$OWNIP    intranet.dev.***REMOVED***.com >> /etc/hosts"
echo "$OWNIP    umg.dev.***REMOVED***.com >> /etc/hosts"
echo "$OWNIP    zaibatsu.dev.***REMOVED***.com >> /etc/hosts"


# enable sites
a2ensite {intranet,sms,umg,website}


# [re]start services
/etc/init.d/samba restart
/etc/init.d/apache2 restart
/etc/init.d/php52-fpm restart
/etc/init.d/php55-fpm restart

# cleanup
rm -rf "$WORKING_DIR"

# reboot box
reboot
exit 0