#!/bin/bash

# for composer update or libs (RH)
# ================

# 1/ check master out
# 2/ run composer update to generate new lock file
# 3/ commit new lock file
# 4/ push the lock file back to master

# pre-requisites
 #===============
#
#-user / key to do the above actions with!!! - codefreeze
#-server to perform action on
#-working directory to use /srv/codefreeze-<random chars>
#-codefreeze ssh key
#-composer installed
# php



# ADD LOGIC SO CAN RUN PER PROJECT

die() { echo $* 1>&2 ; exit 1 ; }

### Settings ###
CODE_FREEZE_KEY="/***REMOVED***/keys/codefreezegitlab"
GIT_REPO="@option.repository_url@"
CODE_FREEZE_ROOT="/tmp"
COMPOSER_OPTIONS="--no-progress --no-interaction --no-scripts"
WORKING_DIR=$(mktemp -d $CODE_FREEZE_ROOT/codefreeze-XXX)
COMPOSER="$CODE_FREEZE_ROOT/composer.phar"

### Validation ###
echo "INFO: Validation checks...."

[ -e "$CODE_FREEZE_KEY" ] || die "ERROR: Code freeze key - $CODE_FREEZE_KEY - does not exist"
which git 2>&1 >/dev/null || die "ERROR: curl is not installed"
which php 2>&1 >/dev/null || die "ERROR: php is not installed"
[ -d "$WORKING_DIR" ] || die "ERROR: Could not create working directory - $WORKING_DIR"


# Download latest composer.phar #
cd "$CODE_FREEZE_ROOT"
curl -sS https://getcomposer.org/installer | php >/dev/null 2>&1 && [ -e "$COMPOSER" ] || die "ERROR: Could not download and setup composer.phar"

### Main ###

# Setup ssh agent and key
eval $(ssh-agent -s) >/dev/null 2>&1
ssh-add $CODE_FREEZE_KEY >/dev/null 2>&1

# Set gitlab user details
if [ -e ~/.gitconfig ]; then
	cp ~/.gitconfig /tmp
	GITCONFIGEXISTS="yes"
fi
git config --global user.name "codefreeze"
git config --global user.email "it-admin@***REMOVED***.com"

# Pull repository down
git clone "$GIT_REPO" "$WORKING_DIR"
cd "$WORKING_DIR"
git checkout master

php "$COMPOSER" $COMPOSER_OPTIONS update || die "ERROR: Failed composer update"
git add composer.lock
git commit -m "Updated libraries via composer on `date`"
git push -u origin master || die "ERROR: Failed pushing changes to repository"


### Cleanup ###
if [ $GITCONFIGEXISTS = "yes" ]; then
	mv /tmp/.gitconfig ~/
else
	git config --global --unset user.name
	git config --global --unset user.email
fi

cd /tmp
kill $SSH_AGENT_PID
rm -rf "$WORKING_DIR"

exit 0