#!/bin/bash

# Script assumes we've pulled down the repo's at least once for each project!

die() { echo $* 1>&2 ; exit 1 ; }
### Settings ###
#TIMESTAMP=$(date +%Y-%m-%d-%H%M)
DEPLOY_KEY="/***REMOVED***/keys/cl_deploy"
PROJECTS_DIR="/var/lib/webistrano/git"
GIT_OPTIONS="--force"
RELEASE="@option.tag@"
PROJECTS="@option.projects@"
BUILDSCRIPT="/***REMOVED***/bin/packdist"
APP_ENVIRONMENT="@option.environment@"

### Validation ###
echo "Validation checks...."
which git >/dev/null 2>&1 || die "ERROR: git is not installed"
[ -e "$DEPLOY_KEY" ] && echo "INFO: Deployment key found - $DEPLOY_KEY"  || die "ERROR: Deployment key - $DEPLOY_KEY - does not exist"
[ -d "$PROJECTS_DIR" ] && echo "INFO: Projects directory found - $PROJECTS_DIR"  || die "ERROR: Projects directory - $PROJECTS_DIR - does not exist"
[ -e "$BUILDSCRIPT" ] || die "ERROR: Build script not found"


# Pull latest code
git_pull () {
  PROJECT="$1"
  cd "$PROJECTS_DIR/$PROJECT" || die "ERROR: project does not exist @ $PROJECTS_DIR/$PROJECT"
  echo "INFO: Refreshing $PROJECT...."
  echo "INFO: origin URLs:"
  #git remote -v
  ssh-agent bash -c "ssh-add $DEPLOY_KEY >/dev/null 2>&1 && git fetch --tags --all" || die "ERROR: Git clone from $GIT_REPO failed"
}

# Checkout latest release
git_checkout () {
  PROJECT="$1"
  cd "$PROJECTS_DIR/$PROJECT" || die "ERROR: project does not exist @ $PROJECTS_DIR/$PROJECT"
  echo "INFO: checking out release $GIT_TAG for $PROJECT...."
  ssh-agent bash -c "ssh-add $DEPLOY_KEY >/dev/null 2>&1 && git checkout $GIT_OPTIONS $RELEASE >/dev/null 2>&1" || die "ERROR: Could not checkout tag:$RELEASE for $PROJECT"
  # If there are issues, as an alternative, blow away folder and do a new pull / clone
}

build_and_dist () {
	PROJECT="$1"
	cd "$PROJECTS_DIR/$PROJECT/build" || die "ERROR: project build directory does not exist @ $PROJECTS_DIR/$PROJECT"
	echo "INFO: building and distributing $PROJECT"
	$BUILDSCRIPT $APP_ENVIRONMENT >/dev/null 2>&1 || die "ERROR: failed to build and distribute $PROJECT"

}

### MAIN ###

# Refresh sources from git
for project in $PROJECTS; do git_pull $project; done

# Checkout tag / release
for project in $PROJECTS; do
  if [[ "$project" != "yii" && "$project" != "offspring" ]]; then
    git_checkout $project
  fi
done

# Build and publish project to bishop
for project in $PROJECTS; do build_and_dist "$project"; done

### no more steps
#echo "INFO: Build succeeded"
exit 0