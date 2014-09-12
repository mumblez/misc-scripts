#!/bin/bash

# POC for specialist symfony deployment

die() { echo $* 1>&2 ; exit 1 ; }
### Settings ###
#TIMESTAMP=$(date +%Y-%m-%d-%H%M)
PHP="/usr/bin/php"
# in future add a check to see if systemd init
PHP_FPM="/etc/init.d/php5-fpm"
SITE_USER="@node.CL_USER@"
SITE_GROUP="www-data"
DEPLOY_KEY="/***REMOVED***/web/cl_deploy"
GIT_REPO="@option.repository_url@"
GIT_OPTIONS="--recursive" #(optional, if using submodules)
GIT_BRANCH="@option.branch@"
GIT_TAG="@option.tag@"
REAL_DIR="/***REMOVED***/lib/php5/symfony2"
SYMFONY_ROOT="/home/@node.CL_USER@/dev/git_repos/symfony_repos"
SYMFONY_BINARIES_ROOT="/home/@node.CL_USER@/dev/git_repos/binaries"
DEPLOY_ROOT="${SYMFONY_ROOT}/@option.repository@"
#SHARED_ROOT="${DEPLOY_ROOT}/shared"
#DEPLOY_DIR="${DEPLOY_ROOT}/${TIMESTAMP}"
WEBROOT="/***REMOVED***/www/specialist-extranet"
APP_ENV="@option.environment@"
COMPOSER="${SYMFONY_BINARIES_ROOT}/composer.phar"
#COMPOSER_OPTIONS="--no-interaction --working-dir=$DEPLOY_DIR"
COMPOSER_OPTIONS="--no-progress --no-interaction"
CONSOLE="${DEPLOY_ROOT}/app/console"
CONSOLE_OPTIONS="--env=dev"
SYMFONY_PARAMS_FILE="$DEPLOY_DIR/app/config/parameters.$APP_ENV.yml"
TMP_SCRIPT=$(mktemp /tmp/deploy-XXX.sh)
chmod +x $TMP_SCRIPT
chown $SITE_USER:$SITE_GROUP $TMP_SCRIPT


# add production specific settings
if [[ "$APP_ENV" == "prod" ]]; then
	COMPOSER_OPTIONS="$COMPOSER_OPTIONS --no-dev --optimize-autoloader"
	CONSOLE_OPTIONS="--env=prod --no-debug"
fi

### Validation ###
echo "INFO: Validation checks...."
id "$SITE_USER" && echo "INFO: Site user - $SITE_USER found" || die "ERROR: User $SITE_USER does not exist"
grep "$SITE_GROUP" /etc/group && echo "INFO: Site group - $SITE_GROUP found" || die "ERROR: Group $SITE_GROUP does not exist"
[ -e "$DEPLOY_KEY" ] && echo "INFO: Deployment key found - $DEPLOY_KEY"  || die "ERROR: Deployment key - $DEPLOY_KEY - does not exist"
[ -e "$PHP_FPM" ] || die "ERROR: $PHP_FPM does not exist"
[ -e "$PHP" ] || die "ERROR: $PHP does not exist"
which curl >/dev/null 2>&1 || die "ERROR: curl is not installed"
which git >/dev/null 2>&1 || die "ERROR: git is not installed"


# Download latest composer.phar #
cd "$SYMFONY_BINARIES_ROOT/binaries"
curl -sS https://getcomposer.org/installer | $PHP >/dev/null 2>&1 && [ -e "$COMPOSER" ] || die "ERROR: Could not download and setup composer.phar"
chown "$SITE_USER":"$SITE_GROUP" "$COMPOSER"


## REPLACE WHEN SALTSTACK SETUP AND NAMESPACE SORTED FOR COMMON REPOS
# Setup specialist-extranet - in future, when common repo's moved into its own namespace, loop this routine for all repo's in ***REMOVED***_web_v2 namespace
cd /etc/php5/fpm/pool.d
## Setup user as owner, so cache and log access isn't a problem (user pulls files down as themselves)
sed "s/^user =.*/user = $SITE_USER/" -i specialist-extranet.conf


# Setup symfony dir incase overwritten / removed from old deploys
#[ ! -d "$REAL_DIR" ] && mkdir "$REAL_DIR"
#[ ! -d "$SHARED_ROOT" ] && mkdir "$SHARED_ROOT"

mkdir -p "$SYMFONY_ROOT"
mkdir -p "$SYMFONY_BINARIES_ROOT"
mkdir -p "$DEPLOY_ROOT"
mkdir -p "$REAL_DIR"

## Cleanup previous releases ###
#find "$DEPLOY_ROOT" -type d -mtime +4 -exec rm -rf {} \;

# Create new deployment directory
mkdir "$DEPLOY_ROOT" || die "ERROR: Failed to create deployment directory - $DEPLOY_DIR"


#Pull latest code
ssh-agent bash -c "ssh-add $DEPLOY_KEY >/dev/null 2>&1 && git clone $GIT_REPO $DEPLOY_ROOT $GIT_OPTIONS" || die "ERROR: Git clone from $GIT_REPO failed"

# or if hot fix simply update???


cd $DEPLOY_ROOT
git checkout "$GIT_BRANCH" # (just leave on master?)


### PULL PROD / TEST SETTINGS FROM CONFIG MGT ###
# or symlink outside releases dir for now

# symlink parameters = change in future to setup via salt / config mgt
#[ -e "$SYMFONY_PARAMS_FILE" ] || die "ERROR: $SYMFONY_PARAMS_FILE does not exist"
#[ -e "$SYMFONY_PARAMS_FILE" ] || echo "WARNING: $SYMFONY_PARAMS_FILE does not exist"
ln -snf "$DEPLOY_ROOT/app/config/parameters.$APP_ENV.yml" "$DEPLOY_ROOT/app/config/parameters.yml"


### REPLACE apache settings from config mgt ###

### Add cron from config mgt ###

#####
###
###

# incase shared vendor directory doesn't exist
#if [ ! -d "${SHARED_ROOT}/vendor" ]; then
#  mkdir "${SHARED_ROOT}/vendor"
#  cp -rf "$DEPLOY_DIR/vendor/." "${SHARED_ROOT}/vendor"
#  chown "$SITE_USER":"$SITE_GROUP" "${SHARED_ROOT}/vendor" -R
#  rm -rf "$DEPLOY_DIR/vendor"
#fi

# replace and symlink vendors directory

#if [ -e "$DEPLOY_DIR/vendor" ]; then
#  rm -rf "$DEPLOY_DIR/vendor" && echo "INFO: ${DEPLOY_DIR}/vendor deleted"
#fi

# replace and symlink vendors directory
#ln -snf "${SHARED_ROOT}/vendor" "${DEPLOY_DIR}/"
#chmod 775 "${SHARED_ROOT}/vendor" -R
#chown -h "$SITE_USER":"$SITE_GROUP" "${DEPLOY_DIR}/vendor"

# Set permissions
chown "$SITE_USER:$SITE_GROUP" "$DEPLOY_ROOT" -R

# fix doctrine bugs
rm -f "${DEPLOY_ROOT}/bin/doctrine"
rm -f "${DEPLOY_ROOT}/bin/doctrine.php"


cd "$DEPLOY_ROOT"
sudo -u "$SITE_USER" "$PHP" "$COMPOSER" self-update && echo "INFO: Composer - self updated" || die "ERROR: Composer: self update failed"
#sudo -u "$SITE_USER" "$PHP" "$COMPOSER" $COMPOSER_OPTIONS install && echo "INFO: Composer - updated" || die "ERROR: Composer: update failed"
#sudo -u "$SITE_USER" "$PHP" "$COMPOSER" $COMPOSER_OPTIONS update && echo "INFO: Composer - updated" || die "ERROR: Composer: update failed"

# We create the script so we can run a few actions in one step as the sudo'ed user
# primarily to setup ssh-agent, add the deployment key and then run our composer install step,
# this is so we can pull from our private repo's using composer.
cat > ${TMP_SCRIPT} <<EOF
#!/bin/bash
eval \$(ssh-agent -s)
ssh-add $DEPLOY_KEY
"$PHP" "$COMPOSER" $COMPOSER_OPTIONS install
kill \$SSH_AGENT_PID
EOF

sudo -u "$SITE_USER" /bin/bash ${TMP_SCRIPT} || die "ERROR: Composer: update failed"
sudo -u "$SITE_USER" "$PHP" "$CONSOLE" cache:clear $CONSOLE_OPTIONS && echo "INFO: Console - cache cleared" || die "ERROR: Console: cache clear failed"
sudo -u "$SITE_USER" "$PHP" "$CONSOLE" assetic:dump $CONSOLE_OPTIONS && echo "INFO: Console - dump assets" || die "ERROR: Console: dumping assets failed"
sudo -u "$SITE_USER" "$PHP" "$CONSOLE" assets:install $CONSOLE_OPTIONS && echo "INFO: Console - install assets" || die "ERROR: Console: installing assets failed"

# make cache and log dir writeable
chmod 777 "$DEPLOY_ROOT/app/logs" -R
chmod 777 "$DEPLOY_ROOT/app/cache" -R

# document
#ln -snf "$DEPLOY_DIR/app/config/parameters.$APP_ENV.yml" "$DEPLOY_DIR/app/config/parameters.yml"


#symlink deploy_dir to real_dir
ln -snf "$DEPLOY_DIR" "$REAL_DIR" && echo "INFO: Symlinked deployment release directory - $DEPLOY_DIR to $REAL_DIR" || die "ERROR: Symlinking deployment release directory - $DEPLOY_DIR to $REAL_DIR failed"

# Set permission to symlink (incase apache only follows symlinks with same owner)
chown -h "$SITE_USER":"$SITE_GROUP" "$REAL_DIR" -R

#symlink web***REMOVED***
ln -snf "$REAL_DIR/web" "$WEBROOT" && echo "INFO: Symlinked deployment release web ***REMOVED*** - $REAL_DIR to $WEBROOT" || die "ERROR: Symlinking deployment release web***REMOVED*** - $REAL_DIR to $WEBROOT failed"

# Set permission to web***REMOVED*** (incase apache only follows symlinks with same owner)
chown -h "$SITE_USER":"$SITE_GROUP" "$WEBROOT"

# Restart php-fpm as it keeps handles open from previous files!
"$PHP_FPM" restart || die "ERROR: Failed to restart $PHP_FPM service"

# DB migration tasks?????

# Clear APC / zendopcode cache?

# Restart apache
/etc/init.d/apache2 restart

### no more steps
echo "INFO: Deployment suceeded!"

# CLEANUP 
echo "INFO: Cleaning up..."
# Clearing old releases
#CURRENT_RELEASE=$(basename $(readlink $REAL_DIR))
#RECENT_RELEASES=$(ls -tr1 "$DEPLOY_ROOT" | grep -vE "shared|$CURRENT_RELEASE" | tail -n4)
#for OLD_RELEASE in $(ls -tr1 "$DEPLOY_ROOT" | grep -vE "shared|$CURRENT_RELEASE"); do
#	if ! echo "$OLD_RELEASE" | grep -q "$RECENT_RELEASES"; then
#		echo "INFO: Deleted old release - $OLD_RELEASE"
#		rm -rf "${DEPLOY_ROOT}/${OLD_RELEASE}"
#	fi
#done

# Delete tmp script
rm -f "$TMP_SCRIPT"
exit 0