#!/bin/bash

die() { echo $* 1>&2 ; exit 1 ; }
### Settings ###
TIMESTAMP=$(date +%Y-%m-%d-%H%M)
PHP=/usr/local/php55/bin/php
#PHP=`which php`
SITE_USER="www-data"
SITE_GROUP="www-data"
DEPLOY_KEY=/***REMOVED***/keys/cl_deploy
GIT_REPO=@option.Git_Repository@
GIT_OPTIONS="--recursive" #(optional, if using submodules)
REAL_DIR=/***REMOVED***/lib/php5/Symfony2
#COMPOSER="$REAL_DIR"/composer.phar
#COMPOSER_OPTIONS="--no-interaction --working-dir=$REAL_DIR"
#CONSOLE="$REAL_DIR"/app/console
DEPLOY_ROOT=/srv/symfony/releases
SHARED_ROOT="${DEPLOY_ROOT}/shared"
DEPLOY_DIR="${DEPLOY_ROOT}/${TIMESTAMP}"
WEBROOT=/***REMOVED***/www/Symfony2
COMPOSER="$DEPLOY_DIR"/composer.phar
COMPOSER_OPTIONS="--no-interaction --working-dir=$DEPLOY_DIR"
CONSOLE="$DEPLOY_DIR"/app/console

### Validation ###
echo "Validation checks...."
id "$SITE_USER" && echo "Site user - $SITE_USER found" || die "ERROR: User $SITE_USER does not exist"
grep "$SITE_GROUP" /etc/group && echo "Site group - $SITE_GROUP found" || die "ERROR: Group $SITE_GROUP does not exist"
[ -e "$DEPLOY_KEY" ] && echo "Deployment key found - $DEPLOY_KEY"  || die "ERROR: Deployment key - $DEPLOY_KEY - does not exist"

## Cleanup previous releases ###
# find "$DEPLOY_ROOT" -type d -mtime +2 -exec rm -rf {} \;

# Create new deployment directory
mkdir "$DEPLOY_DIR" || die "ERROR: Failed to create deployment directory - $DEPLOY_DIR"


#Pull latest code
ssh-agent bash -c "ssh-add $DEPLOY_KEY >/dev/null 2>&1 && git clone $GIT_REPO $DEPLOY_DIR $GIT_OPTIONS" || die "ERROR: Git clone from $GIT_REPO failed"
chown "$SITE_USER:$SITE_GROUP" "$DEPLOY_DIR" -R

# cd $DEPLOY_DIR
# git checkout ??????????? (just leave on master?)


# symlink parameters
ln -snf "$DEPLOY_DIR/app/config/parameters.qa.yml" "$DEPLOY_DIR/app/config/parameters.yml"

# replace and symlink vendors directory
rm -rf "$DEPLOY_DIR/vendor"
ln -snf "${SHARED_ROOT}/vendor" "$DEPLOY_DIR/vendor"
chown -h "$SITE_USER":"$SITE_GROUP" "$DEPLOY_DIR/vendor"

# make cache and log dir writeable
chmod 777 "$DEPLOY_DIR/app/logs" -R
chmod 777 "$DEPLOY_DIR/app/cache" -R

cd "$REAL_DIR"
sudo -u "$SITE_USER" "$PHP" "$COMPOSER" $COMPOSER_OPTIONS self-update && echo "Composer: self updated" || die "ERROR: Composer: self update failed"
sudo -u "$SITE_USER" "$PHP" "$COMPOSER" $COMPOSER_OPTIONS update && echo "Composer: updated" || die "ERROR: Composer: update failed"
sudo -u "$SITE_USER" "$PHP" "$CONSOLE" cache:clear --env=dev && echo "Console: cache cleared" || die "ERROR: Console: cache clear failed"
sudo -u "$SITE_USER" "$PHP" "$CONSOLE" cache:clear --env=prod && echo "Console: cache cleared" || die "ERROR: Console: cache clear failed"

# make cache and log dir writeable
chmod 777 "$DEPLOY_DIR/app/logs" -R
chmod 777 "$DEPLOY_DIR/app/cache" -R

#symlink deploy_dir to real_dir
ln -snf "$DEPLOY_DIR" "$REAL_DIR" && echo "Symlinked deployment release directory - $DEPLOY_DIR to $REAL_DIR" || die "ERROR: Symlinking deployment release directory - $DEPLOY_DIR to $REAL_DIR failed"

# Set permission to symlink (incase apache only follows symlinks with same owner)
chown -h "$SITE_USER":"$SITE_GROUP" "$REAL_DIR" -R

#symlink web***REMOVED***
ln -snf "$REAL_DIR/web" "$WEBROOT" && echo "Symlinked deployment release web ***REMOVED*** - $REAL_DIR to $WEBROOT" || die "ERROR: Symlinking deployment release web***REMOVED*** - $REAL_DIR to $WEBROOT failed"

# Set permission to web***REMOVED*** (incase apache only follows symlinks with same owner)
chown -h "$SITE_USER":"$SITE_GROUP" "$WEBROOT"

### no more steps
echo "Deployment suceeded!"
exit 0
