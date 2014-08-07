#!/bin/bash
# Script to setup a new user on a new dev-vm after a fresh clone
# of the template.
# Ensure svn account is created first

die() { echo $* 1>&2 ; exit 1 ; }

# settings
USER=		# passed from rundeck - create rd.json to use this value to work out other values and to
# check it also doesn't exist (and maybe setup SVN)
PASSWORD=   # passed from rundeck
OWNIP=	    # rundeck json scans for free IPs and passes one in that's available?
HOSTNAME=   # passed from rundeck
TOOLS="chpasswd svn git adduser"
WORKING_DIR=$(mktemp -d /tmp/new_user_setup_XXX)
NEW_DIRS=$(mktemp $WORKING_DIR/new_dirs_XXX.txt)
SVN_URL="https://***REMOVED***.***REMOVED***.com/svn/trunk/projects"

# validation

for TOOL in $TOOLS; do
	which chpasswd >/dev/null 2>&1 || die "ERROR: $TOOL is not installed"
done


# create new user
adduser --ingroup dev --force-badname $USER
echo "$USER:$PASSWORD" | chpasswd

# new directories
cat > ${NEW_DIRS} <<EOF
/***REMOVED***/lib/shared
/***REMOVED***/lib/php5/dwoo/compiled
/***REMOVED***/lib/php5/offspring
/***REMOVED***/config/common
/***REMOVED***/secure/website
/***REMOVED***/var/web/data/files.{registration,hrcv,production,attachment}
/***REMOVED***/var/cache/dwoo/offspring
/***REMOVED***/lib/php5/offspring
/***REMOVED***/lib/{js,templates}
/***REMOVED***/log/{intranet,website}
EOF

while read line; do
	mkdir -p "$line"
done < "${NEW_DIRS}"


# svn pull - account needs to exist on svn to pull automatically
sudo -u "$USER" mkdir -p ~/dev/{infrastructure,projects}
sudo -u "$USER" svn checkout --depth empty "$SVN_URL" ~/dev/projects --username "$USER" --password "$PASSWORD"
sudo -u "$USER" svn checkout "$SVN_URL" ~/dev/infrastructure
cd /home/"$USER"/dev/infrastructure
sudo -u "$USER" svn up intranet website common


# create symlinks



# permissions
chown $USER:dev -R /home/$USER/dev
chmod 777 /***REMOVED***/lib/php5/dwoo/compiled
chmod 777 -R /***REMOVED***/var/compiled/
chmod 777 -R /***REMOVED***/var/cache/
chmod 777 -R /***REMOVED***/log/

# apache



# set IP



# setup /etc/hosts



# enable sites
a2ensite {intranet,sms,umg}


# [re]start services


# cleanup
rm -rf "$WORKING_DIR"