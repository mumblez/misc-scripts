#!/bin/bash

# for code freeze (RH):
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

#
#pre-requisites
#===============
#
#codefree / ***REMOVED***
#
#-user / key to do the above actions with!!! - codefreeze
#-server to perform action on - 
#-codefreeze ssh key
#-working directory to use /tmp/codefreeze-<random chars>




# ADD LOGIC SO CAN RUN PER PROJECT

die() { echo $* 1>&2 ; exit 1 ; }

### Settings ###
CODE_FREEZE_KEY="/***REMOVED***/keys/codefreezegitlab"
GIT_REPO="@option.repository_url@"
GIT_TAG="@option.tag@"
TAG_LATEST="@option.tag_latest@"
WORKING_DIR=$(mktemp -d /tmp/codefreeze-XXX)
GITCONFIGEXISTS="no"

### Validation ###
echo "INFO: Validation checks...."
[ -e "$CODE_FREEZE_KEY" ] || die "ERROR: Code freeze key - $CODE_FREEZE_KEY - does not exist"
which git 2>&1 >/dev/null || die "ERROR: curl is not installed"
[ -d "$WORKING_DIR" ] || die "ERROR: Could not create working directory - $WORKING_DIR"

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
git checkout release || die "ERROR: Failed to checkout release branch"
###
# PULL CHANGES IN FROM MASTER
git merge master --no-ff || die "ERROR: Failed to merge changes from master"
git push -u origin release || die "ERROR: Failed to release branch to repository"
### ADD TAG
git tag -f -a "$GIT_TAG" -m "Code freeze" || die "ERROR: Failed to create new tag: $GIT_TAG"
git push -f --tags || die "ERROR: Failed to push tag to repository"



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