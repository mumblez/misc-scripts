#!/bin/bash

# POC for specialist symfony deployment

die() { echo $* 1>&2 ; exit 1 ; }
### Settings ###
TIMESTAMP=$(date +%Y-%m-%d-%H%M)
PHP="/usr/local/php55/bin/php"
PHP_FPM="/etc/init.d/php5-fpm"
SITE_USER="www-data"
SITE_GROUP="www-data"
DEPLOY_KEY="/***REMOVED***/keys/cl_deploy"
GIT_REPO="@option.Git_Repository@"
GIT_OPTIONS="--recursive" #(optional, if using submodules)
GIT_TAG_BR="@option.branch@"
REAL_DIR="/***REMOVED***/lib/php5/symfony2"
SYMFONY_ROOT="/srv/symfony"
DEPLOY_ROOT="${SYMFONY_ROOT}/releases"
SHARED_ROOT="${DEPLOY_ROOT}/shared"
DEPLOY_DIR="${DEPLOY_ROOT}/${TIMESTAMP}"
WEBROOT="/***REMOVED***/www/symfony2"
COMPOSER="${SYMFONY_ROOT}/binaries/composer.phar"
COMPOSER_OPTIONS="--no-interaction --working-dir=$DEPLOY_DIR"
CONSOLE="$DEPLOY_DIR/app/console"
APP_ENV="@option.environment@"
CONSOLE_OPTIONS="--env=$APP_ENV"
SYMFONY_PARAMS_FILE="$DEPLOY_DIR/app/config/parameters.$APP_ENV.yml"

# add production specific settings
if [[ "$APP_ENV" == "prod" ]]; then
	COMPOSER_OPTIONS="$COMPOSER_OPTIONS --no-dev --optimize-autoloader"
	CONSOLE_OPTIONS="$CONSOLE_OPTIONS --no-debug"
fi

### Validation ###
echo "Validation checks...."
id "$SITE_USER" && echo "Site user - $SITE_USER found" || die "ERROR: User $SITE_USER does not exist"
grep "$SITE_GROUP" /etc/group && echo "Site group - $SITE_GROUP found" || die "ERROR: Group $SITE_GROUP does not exist"
[ -e "$DEPLOY_KEY" ] && echo "Deployment key found - $DEPLOY_KEY"  || die "ERROR: Deployment key - $DEPLOY_KEY - does not exist"
[ -e "$PHP_FPM" ] || die "ERROR: $PHP_FPM does not exist"
[ -e "$PHP" ] || die "ERROR: $PHP does not exist"
which curl 2>&1 >/dev/null || die "ERROR: curl is not installed"

# Download latest composer.phar #
cd "$SYMFONY_ROOT/binaries"
curl -sS https://getcomposer.org/installer | $PHP 2>&1 >/dev/null && [ -e "$COMPOSER" ] || die "ERROR: Could not download and setup composer.phar"
chown "$SITE_USER":"$SITE_GROUP" "$COMPOSER"


# Setup symfony dir incase overwritten / removed from old deploys
#[ ! -d "$REAL_DIR" ] && mkdir "$REAL_DIR"
[ ! -d "$SHARED_ROOT" ] && mkdir "$SHARED_ROOT"

## Cleanup previous releases ###
#find "$DEPLOY_ROOT" -type d -mtime +4 -exec rm -rf {} \;

# Create new deployment directory
mkdir "$DEPLOY_DIR" || die "ERROR: Failed to create deployment directory - $DEPLOY_DIR"


#Pull latest code
ssh-agent bash -c "ssh-add $DEPLOY_KEY >/dev/null 2>&1 && git clone $GIT_REPO $DEPLOY_DIR $GIT_OPTIONS" || die "ERROR: Git clone from $GIT_REPO failed"

# or if hot fix simply update???


cd $DEPLOY_DIR
git checkout "$GIT_TAG_BR" # (just leave on master?)


### PULL PROD / TEST SETTINGS FROM CONFIG MGT ###

# symlink parameters = change in future to setup via salt / config mgt
[ -e "$SYMFONY_PARAMS_FILE" ] || die "ERROR: $SYMFONY_PARAMS_FILE does not exist"
ln -snf "$DEPLOY_DIR/app/config/parameters.$APP_ENV.yml" "$DEPLOY_DIR/app/config/parameters.yml"


### REPLACE apache settings from config mgt ###

### Add cron from config mgt ###

#####
###
###

# incase shared vendor directory doesn't exist
if [ ! -d "${SHARED_ROOT}/vendor" ]; then
  mkdir "${SHARED_ROOT}/vendor"
  cp -rf "$DEPLOY_DIR/vendor/." "${SHARED_ROOT}/vendor"
  chown "$SITE_USER":"$SITE_GROUP" "${SHARED_ROOT}/vendor" -R
  rm -rf "$DEPLOY_DIR/vendor"
fi

# replace and symlink vendors directory
ln -snf "${SHARED_ROOT}/vendor" "$DEPLOY_DIR/vendor"
chmod 775 "${SHARED_ROOT}/vendor" -R
chown -h "$SITE_USER":"$SITE_GROUP" "$DEPLOY_DIR/vendor"

# Set permissions
chown "$SITE_USER:$SITE_GROUP" "$DEPLOY_DIR" -R

# make cache and log dir writeable
chmod 777 "$DEPLOY_DIR/app/logs" -R
chmod 777 "$DEPLOY_DIR/app/cache" -R

cd "$DEPLOY_DIR"
sudo -u "$SITE_USER" "$PHP" "$COMPOSER" $COMPOSER_OPTIONS self-update && echo "INFO: Composer - self updated" || die "ERROR: Composer: self update failed"
sudo -u "$SITE_USER" "$PHP" "$COMPOSER" $COMPOSER_OPTIONS update && echo "INFO: Composer - updated" || die "ERROR: Composer: update failed"
sudo -u "$SITE_USER" "$PHP" "$CONSOLE" cache:clear "$CONSOLE_OPTIONS" && echo "INFO: Console - cache cleared" || die "ERROR: Console: cache clear failed"
sudo -u "$SITE_USER" "$PHP" "$CONSOLE" assetic:dump "$CONSOLE_OPTIONS" && echo "INFO: Console - dump assets" || die "ERROR: Console: dumping assets failed"
sudo -u "$SITE_USER" "$PHP" "$CONSOLE" assetic:install "$CONSOLE_OPTIONS" && echo "INFO: Console - install assets" || die "ERROR: Console: installing assets failed"

# make cache and log dir writeable
chmod 775 "$DEPLOY_DIR/app/logs" -R
chmod 775 "$DEPLOY_DIR/app/cache" -R

#symlink deploy_dir to real_dir
ln -snf "$DEPLOY_DIR" "$REAL_DIR" && echo "Symlinked deployment release directory - $DEPLOY_DIR to $REAL_DIR" || die "ERROR: Symlinking deployment release directory - $DEPLOY_DIR to $REAL_DIR failed"

# Set permission to symlink (incase apache only follows symlinks with same owner)
chown -h "$SITE_USER":"$SITE_GROUP" "$REAL_DIR" -R

#symlink web***REMOVED***
ln -snf "$REAL_DIR/web" "$WEBROOT" && echo "Symlinked deployment release web ***REMOVED*** - $REAL_DIR to $WEBROOT" || die "ERROR: Symlinking deployment release web***REMOVED*** - $REAL_DIR to $WEBROOT failed"

# Set permission to web***REMOVED*** (incase apache only follows symlinks with same owner)
chown -h "$SITE_USER":"$SITE_GROUP" "$WEBROOT"

# Restart php-fpm as it keeps handles open from previous files!
"$PHP_FPM" restart || die "ERROR: Failed to restart $PHP_FPM service"

# DB migration tasks?????

# Clear APC / zendopcode cache?

# Restart apache
/etc/init.d/apache2 restart

### no more steps
echo "Deployment suceeded!"
exit 0
