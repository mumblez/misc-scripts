#!/bin/bash

# re-tag 'latest' each time there's a new release, called from post-receive hook

die() { echo $* 1>&2 ; exit 1 ; }

### Settings ###
CODE_FREEZE_KEY="/mnt/ssd/codefreezegitlab"
TEMP_AREA="/mnt/ssd/temp"
WORKING_DIR=$(mktemp -d ${TEMP_AREA}/latest-tag-XXX)
GITCONFIGEXISTS="no"
GIT_REPO="$1"
GIT_TAG="$2"

### Validation ###
#echo "INFO: Validation checks...."
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
git clone "file://${GIT_REPO}" "$WORKING_DIR" &>/dev/null
cd "$WORKING_DIR"

# Get latest valid tag
#LATEST_TAG=$(git tag -l | grep -E ".*v?[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | sort -rV | head -n 1)
LATEST_COMMIT=$(git rev-parse "$GIT_TAG")

# Force latest tag creation
git tag -f latest "$LATEST_COMMIT"

# Force push
git push -f origin latest


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
