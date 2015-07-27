#!/bin/bash

die() { echo $* 1>&2 ; exit 1 ; }
# Settings

PROJECT="@option.project@"
WORKING_DIR=$(mktemp -d /mnt/ssd/temp/${PROJECT}-version-update-XXX)
NEW_VERSION="@option.new_version@"
#GIT_OPTIONS='--author="Code Freeze <it-admin@***REMOVED***.com>"'
#GIT_REPOS_FILE_ROOT="/mnt/ssd/git_repositories/***REMOVED***"
FREEZE_KEY="/***REMOVED***/keys/codefreezegitlab"
#REPO_URL="//${GIT_REPOS_FILE_ROOT}/${PROJECT}.git"
REPO_URL="git@***REMOVED***.***REMOVED***.com:***REMOVED***/${PROJECT}.git"
GITCONFIGEXISTS="no"

#REPO_ID=$(curl --header "PRIVATE-TOKEN: ${GL_KEY}" -k -s "${GL_API_URL}/projects/all?per_page=10000" | jq --arg NSWP "${GL_CL_NAMESPACE}/${PROJECT}" '.[] | select(.path_with_namespace == $NSWP ) | .id')
#[ -z $REPO_ID ] && die "ERROR: Failed to find project id on gitlab!"

# Cleanup
cleanup () {
    cd /tmp
	#rm -rf "$WORKING_DIR"
	if [ $GITCONFIGEXISTS = "yes" ]; then
	    mv /tmp/.gitconfig ~/
    else
	    git config --global --unset user.name
	    git config --global --unset user.email
    fi
    kill $SSH_AGENT_PID
}

trap cleanup EXIT

cd "$WORKING_DIR" || die "ERROR: Failed to create and cd into $WORKING_DIR"

# Setup ssh agent and key
eval $(ssh-agent -s) >/dev/null 2>&1
ssh-add $FREEZE_KEY >/dev/null 2>&1

# Set gitlab user details
if [ -e ~/.gitconfig ]; then
	cp ~/.gitconfig /tmp
	GITCONFIGEXISTS="yes"
fi

git config --global user.name "Code Freeze"
git config --global user.email "it-admin@***REMOVED***.com"


git clone $REPO_URL &>/dev/null || die "ERROR: Failed to clone $REPO_URL"
cd "$PROJECT"

# find and checkout latest sprint branch
CHECKOUT_BRANCH=$(git branch -r | grep 'sprint-' | head -n1 | cut -d'/' -f2)
[ -z "$CHECKOUT_BRANCH" ] && CHECKOUT_BRANCH=$(git branch -r | grep 'release-' | head -n1 | cut -d'/' -f2)
[ -z "$CHECKOUT_BRANCH" ] && CHECKOUT_BRANCH="master"

echo "INFO: Checkout branch = $CHECKOUT_BRANCH"
git checkout "$CHECKOUT_BRANCH" || die "ERROR: Failed to checkout $CHECKOUT_BRANCH"

# change version values in files (2)
FILE1="config/prod/version"
CURRENT_VERSION=$(cat "$FILE1" | cut -d'=' -f2)
[[ "$CURRENT_VERSION" == "$NEW_VERSION" ]] && die "ERROR: Current and new version are the same!"
echo "VERSION=${NEW_VERSION}" >> "$FILE1"
[[ "$NEW_VERSION" == $(cat "$FILE1" | cut -d'=' -f2 | sort -rV | head -n1) ]] || die "ERROR: Entered version is lower than current version!"
echo "VERSION=${NEW_VERSION}" > "$FILE1"

FILE2="build/changelog"
NEXT_VERSION=$(echo "$NEW_VERSION" | awk 'BEGIN { FS = "." } { print $1"."$2"."$3+1 }')
echo -e "Version $NEXT_VERSION\n---\n  * Started on "`date`"\n\n" | cat - build/changelog >/tmp/changelog
mv /tmp/changelog build/changelog
rm -f /tmp/changelog

# set user to codefreeze
#git config user.name "codefreeze"
#git config user.email "it-admin@***REMOVED***.com"

# commit and push

git add "$FILE1"
git add "$FILE2"
#git commit --author="Code Freeze <it-admin@***REMOVED***.com>" -m 'incremented changelog and version' || die "ERROR: Failed to commit changes!"
git commit -m 'incremented changelog and version' || die "ERROR: Failed to commit changes!"
git push -u origin "$CHECKOUT_BRANCH" || die "ERROR: Failed to push changes back to repository!"


# Finish
echo "INFO: Successfully completed version incrementing."