#!/bin/bash

# INITIALISE THE REPO'S FOR FIRST TIME BEFORE RUNNING (e.g. /var/lib/webistrano/git)
# So for multi choice projects we don't have to query, map and pass in git url's
# Temporary until we move to all symfony

die() { echo $* 1>&2 ; exit 1 ; }
### Settings ###
#TIMESTAMP=$(date +%Y-%m-%d-%H%M)
DEPLOY_KEY="/root/keys/cl_deploy"
#PROJECTS_DIR="/var/lib/webistrano/git" # webistrano
PROJECTS_DIR="/srv/git" # bishop
GIT_OPTIONS="--force"
RELEASE="@option.tag@"
PROJECTS="@option.projects@"
BUILDSCRIPT="/cognolink/bin/package"
APP_ENVIRONMENT="@option.environment@"
GIT_URL="git@gitlab.dev.cognolink.com"
GIT_NAMESPACE="cognolink"
#TAG_PREFIX="release-"
PKG_REPO_URL="rundeck@bishop" # change to new repo if non prod in future

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
  if [ ! -d "${PROJECTS_DIR}/${PROJECT}" ]; then
    cd "$PROJECTS_DIR"
    echo "INFO: Initial clone of $PROJECT..."
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git clone ${GIT_URL}:${GIT_NAMESPACE}/${PROJECT}.git" || die "ERROR: Git clone from $GIT_REPO failed"
  else
    cd "${PROJECTS_DIR}/${PROJECT}"
    echo "INFO: Refreshing ${PROJECT}..."
    #echo "INFO: origin URLs:"
    #git remote -v
    #ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git fetch" || die "ERROR: Git fetch from $GIT_REPO failed"
    #ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git fetch --tags" || die "ERROR: Git fetch from $GIT_REPO failed"
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git reset --hard" || die "ERROR: Git reset hard on $GIT_REPO failed"
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git fetch --all" || die "ERROR: Git fetch from $GIT_REPO failed"
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git fetch --tags" || die "ERROR: Git fetch new tags from $GIT_REPO failed"
    #ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git pull" || die "ERROR: Git reset hard on $GIT_REPO failed"
  fi
}

# Checkout latest release
git_checkout () {
  PROJECT="$1"
  cd "${PROJECTS_DIR}/${PROJECT}"
  # if yii, offspring or sphinx then don't checkout tag, just checkout master
  if [[ "$PROJECT" == "yii" || "$PROJECT" == "sphinx" || "$PROJECT" = "offspring" ]]; then
    echo "INFO: checking out master branch for $PROJECT...."
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git checkout $GIT_OPTIONS master &>/dev/null" || die "ERROR: Could not checkout master branch for $PROJECT"
    ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git pull &>/dev/null" || die "ERROR: Could not update branch for $PROJECT"
  else
    if [[ "$APP_ENVIRONMENT" != "prod" && "$APP_ENVIRONMENT" != "test" && "$APP_ENVIRONMENT" != "training" ]]; then
      if [ -z "$RELEASE" ]; then
        SPRINT_BRANCH=$(git branch -r | cut -d'/' -f2 | grep 'sprint' | sort -rV | head -n1)
        [ -z "$SPRINT_BRANCH" ] && SPRINT_BRANCH=$(git branch -r | cut -d'/' -f2 | grep 'release' | sort -rV | head -n1) # temporary hack until migration complete
        [ -z "$SPRINT_BRANCH" ] && SPRINT_BRANCH="master"
      else
        SPRINT_BRANCH="$RELEASE"
      fi
      echo "INFO: checking out latest sprint/release/master branch - $SPRINT_BRANCH for $PROJECT on $APP_ENVIRONMENT..."
      ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git checkout $GIT_OPTIONS $SPRINT_BRANCH &>/dev/null" || die "ERROR: Could not checkout $SPRINT_BRANCH for $PROJECT"
      ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git pull &>/dev/null" || die "ERROR: Could not update $SPRINT_BRANCH for $PROJECT"
    else
      echo "INFO: checking out release ${RELEASE} for $PROJECT..."
      ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git checkout $GIT_OPTIONS ${RELEASE} &>/dev/null" || die "ERROR: Could not checkout tag:$RELEASE for $PROJECT"
      #ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && git pull &>/dev/null" || die "ERROR: Could not checkout tag:$RELEASE for $PROJECT"
    fi  
  fi
  # If there are issues, as an alternative, blow away folder and do a new pull / clone
}

build_and_dist () {
  PROJECT="$1"
  cd "${PROJECTS_DIR}/${PROJECT}/build" || die "ERROR: project build directory does not exist @ ${PROJECTS_DIR}/${PROJECT}"
  PACKAGE=$(grep Package control | awk {'print $2'})
  echo "INFO: building ${PROJECT}..."
  "$BUILDSCRIPT" "$APP_ENVIRONMENT" &>/dev/null || die "ERROR: failed to build $PROJECT"
  echo "INFO: distributing $1 to package repo..."

  ################### CHANGE 'dists-poc' to 'dists' after testing!!!!!  ############

  # deploy / webistrano
  #rsync -e "ssh" --rsync-path="sudo rsync" $PACK*.deb "${PKG_REPO_URL}:/srv/deb_repository/dists-poc/${APP_ENVIRONMENT}/main/binary-amd64" &>/dev/null || die "ERROR: failed to distribute $PROJECT"
  # app1 / bishop
  #rsync -v $PACKAGE*.deb "/srv/deb_repository/dists-poc/${APP_ENVIRONMENT}/main/binary-amd64" &>/dev/null || die "ERROR: failed to distribute $PROJECT"
  if [[ "$APP_ENVIRONMENT" == "prod" || "$APP_ENVIRONMENT" == "test" ]]; then 
    REPO_PATH="/srv/deb_repository/dists/prod/main/binary-amd64"
  else
    REPO_PATH="/srv/deb_repository/dists/${APP_ENVIRONMENT}/main/binary-amd64"
  fi

  rsync -v $PACKAGE*.deb "$REPO_PATH" &>/dev/null || die "ERROR: failed to distribute $PROJECT"
  chown package:www-data "$REPO_PATH" -R
  #chown package:www-data "/srv/deb_repository/dists/${APP_ENVIRONMENT}/main/binary-amd64" -R
  rm -f $PACKAGE*.deb

  rm -rf "$PROJECTS_DIR/$PROJECT/build/debian" || echo "WARN: failed to delete debian folder from build directory!"
}

### MAIN ###

# Refresh sources from git
for project in $PROJECTS; do git_pull "$project"; done

# Checkout tag / release
for project in $PROJECTS; do git_checkout "$project"; done

# Build and publish project to bishop
for project in $PROJECTS; do build_and_dist "$project"; done

### no more steps

echo "INFO: Build succeeded"
exit 0