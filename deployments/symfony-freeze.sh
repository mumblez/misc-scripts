#!/bin/bash

# for code freeze:
# ================
#  
# 1/ git pull origin/master into origin/release
#  
# needs 1 parameter for into which tagged commit on release, in case we had hotfix on it that got fixed on both release and master already.
#  
# This way there should be no conflict at all, if there is any, stop the process right there
#  
# 2/ push the result back to release
# 3/ tag the merged commit
#  
# need 1 parameter of the new tag name
#  
# -----------------
#  
# 4/ check master out
# 5/ run composer update to generate new lock file
# 6/ commit new lock file
# 7/ push the lock file back to master

#git clone project
#git checkout master
#composer update
#git commit (only new) composer.lock
#git push master
#git checkout release
#git fetch origin (and merge latest changes from master)
#git merge master
#git tag (v.x.x?.?x)
#git push tag
#
#pre-requisites
#===============
#
#codefree / ***REMOVED***777
#
#-user / key to do the above actions with!!! - codefreeze
#-server to perform action on - 
#--setup ***REMOVED*** so that git commits are done as a specific user (codefreeze)
#-working directory to use /srv/codefreeze-<random chars>
#-composer installed
# php



# ADD LOGIC SO CAN RUN PER PROJECT

die() { echo $* 1>&2 ; exit 1 ; }

### Settings ###
CODE_FREEZE_KEY="/***REMOVED***/keys/codefreezegitlab"
GIT_REPO="@option.repository_url@"
WORKING_DIR=$(mktemp -d /tmp/codefreeze-XXX)
GITCONFIGEXISTS="no"

### Validation ###
echo "INFO: Validation checks...."
[ -e "$CODE_FREEZE_KEY" ] || die "ERROR: Code freeze key - $CODE_FREEZE_KEY - does not exist"
which git 2>&1 >/dev/null || die "ERROR: curl is not installed"
[ -d "$WORKING_DIR" ] || die "ERROR: Could not create working directory - $WORKING_DIR"

### Main ###

# Setup ssh agent and key
eval $(ssh-agent -s) 2>&1 >/dev/null
ssh-add $CODE_FREEZE_KEY 2>&1 >/dev/null

# Set gitlab user details
if [ -e ~/.gitconfig ]; then
	cp ~/.gitconfig /tmp
	GITCONFIGEXISTS="yes"
fi
git config --global user.name "codefreeze"
git config --global user.email "it-admin@***REMOVED***.com"

cat ~/.gitconfig

# Pull repository down
git clone "$GIT_REPO" "$WORKING_DIR"
cd "$WORKING_DIR"




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

