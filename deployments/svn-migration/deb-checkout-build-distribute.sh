#!/bin/bash


die() { echo $* 1>&2 ; exit 1 ; }
### Settings ###
#TIMESTAMP=$(date +%Y-%m-%d-%H%M)
DEPLOY_KEY="/***REMOVED***/keys/cl_deploy"
PROJECTS_DIR="/var/lib/webistrano/git"
GIT_OPTIONS="--force"
RELEASE="@option.tag@"
PROJECTS="@option.projects@"
BUILDSCRIPT="/***REMOVED***/bin/package"
APP_ENVIRONMENT="@option.environment@"
GIT_URL="git@***REMOVED***.***REMOVED***.com"
GIT_NAMESPACE="***REMOVED***"
TAG_PREFIX="release-"
PKG_REPO_URL="rundeck@bishop" # change to new repo when testing

### Validation ###
echo "Validation checks...."
which git >/dev/null 2>&1 || die "ERROR: git is not installed"
[ -e "$DEPLOY_KEY" ] && echo "INFO: Deployment key found - $DEPLOY_KEY"  || die "ERROR: Deployment key - $DEPLOY_KEY - does not exist"
[ -d "$PROJECTS_DIR" ] && echo "INFO: Projects directory found - $PROJECTS_DIR"  || die "ERROR: Projects directory - $PROJECTS_DIR - does not exist"
[ -e "$BUILDSCRIPT" ] || die "ERROR: Build script not found"


# Pull latest code
git_pull () {
  PROJECT="$1"
  # if first time then git clone
  if [ ! -d "$PROJECTS_DIR/$PROJECT" ]; then
    cd "$PROJECTS_DIR"
    echo "INFO: Initial clone of $PROJECT..."
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git clone " || die "ERROR: Git clone from $GIT_REPO failed"
  else
    cd "$PROJECTS_DIR/$PROJECT" || die "ERROR: project does not exist @ $PROJECTS_DIR/$PROJECT"
    echo "INFO: Refreshing $PROJECT...."
    #echo "INFO: origin URLs:"
    #git remote -v
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git fetch" || die "ERROR: Git clone from $GIT_REPO failed"
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git fetch --tags" || die "ERROR: Git clone from $GIT_REPO failed"
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git fetch --all" || die "ERROR: Git clone from $GIT_REPO failed"
  fi
}

# Checkout latest release
git_checkout () {
  PROJECT="$1"
  cd "$PROJECTS_DIR/$PROJECT" || die "ERROR: project does not exist @ $PROJECTS_DIR/$PROJECT"
  # if yii, offspring or sphinx then don't checkout tag, just checkout master
  if [[ "$PROJECT" == "yii" || "$PROJECT" == "sphinx" || "$PROJECT" = "offspring" ]]; then
    echo "INFO: checking out master branch for $PROJECT...."
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git checkout $GIT_OPTIONS master &>/dev/null" || die "ERROR: Could not checkout master branch for $PROJECT"
  else
    echo "INFO: checking out release ${TAG_PREFIX}${RELEASE} for $PROJECT...."
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git checkout $GIT_OPTIONS ${TAG_PREFIX}${RELEASE} &>/dev/null" || die "ERROR: Could not checkout tag:$RELEASE for $PROJECT"
  fi
  # If there are issues, as an alternative, blow away folder and do a new pull / clone
}

build_and_dist () {
    PROJECT="$1"
	cd "$PROJECTS_DIR/$PROJECT/build" || die "ERROR: project build directory does not exist @ $PROJECTS_DIR/$PROJECT"
	PACKAGE=$(grep Package control | awk {'print $2'})
	echo "INFO: building and distributing $PROJECT..."
	$BUILDSCRIPT $APP_ENVIRONMENT &>/dev/null || die "ERROR: failed to build $PROJECT"
	#$DISTRIBUTESCRIPT $PACK*.deb $APP_ENVIRONMENT &>/dev/null || die "ERROR: failed to distribute $PROJECT"
	echo "INFO: distributing to $i package repo..."
	# enable agent forwarding
    #scp $PACK*.deb ${PKG_REPO_URL}:/srv/deb_repository/dists-poc/${APP_ENVIRONMENT}/main/binary-amd64 &>/dev/null || die "ERROR: failed to distribute $PROJECT"
    rsync -e "ssh" --rsync-path="sudo rsync" $PACK*.deb ${PKG_REPO_URL}:/srv/deb_repository/dists-poc/${APP_ENVIRONMENT}/main/binary-amd64 &>/dev/null || die "ERROR: failed to distribute $PROJECT"
    #scp $PACK*.deb ${PKG_REPO_URL}:/srv/deb_repository/dists/${APP_ENVIRONMENT}/main/binary-amd64 &>/dev/null || die "ERROR: failed to distribute $PROJECT"
	rm -rf "$PROJECTS_DIR/$PROJECT/build/debian" || echo "WARN: failed to delete debian folder from build directory!"

}

### MAIN ###
set -x
# Refresh sources from git
for project in $PROJECTS; do git_pull $project; done

# Checkout tag / release
for project in $PROJECTS; do git_checkout $project; done


# Build and publish project to bishop
for project in $PROJECTS; do build_and_dist "$project"; done

set +x
### no more steps
echo "INFO: Build succeeded"
exit 0