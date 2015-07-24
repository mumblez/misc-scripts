#!/bin/bash

### SETTINGS ###
die() { echo $* 1>&2 ; exit 1 ; }
TEMP_AREA=/tmp
WORK_DIR=$(mktemp -d $TEMP_AREA/sql_deploy.XXX)
PROJECT="@option.project@" # SINGLE PROJECT
RELEASE="@option.tag@"
RELEASE_PREFIX="release-"
GIT_TAG="${RELEASE_PREFIX}${RELEASE}"
DB_FILE="@option.db_file@"
GITLAB_BASE="***REMOVED***.***REMOVED***.com"
NAMESPACE="***REMOVED***"
DB_PATH="db"
DEPLOY_KEY="/***REMOVED***/keys/cl_deploy"   # GIT
TOOLS="git mysql mktemp curl"
ENVIRONMENT="@option.environment@"


# VALIDATE
## Validate package managed tools
for TOOL in $TOOLS; do
  which $TOOL &>/dev/null || die "ERROR: $TOOL is not installed"
done

## Validate custom tools
[ -e /usr/local/bin/jq ] || { wget -O /usr/local/bin/jq http://stedolan.github.io/jq/download/linux64/jq && chmod +x /usr/local/bin/jq; }


# FUNCTIONS

git_query () {
  CHECKOUT_TYPE="$1"
  case "$CHECKOUT_TYPE" in
    branch ) C_TYPE="--heads" ;;
    tag ) C_TYPE="--tags" ;;
  esac

  ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && \
  git ls-remote $C_TYPE git@${GITLAB_BASE}:${NAMESPACE}/${project}.git" | grep -v '\^{}'
}


configure_checkout_type () {
  # validate tag, if not valid look for latest sprint branch
  # else release branch else finally just master branch
  FINAL_CHECKOUT_TYPE="tag"
  if [ -z "$GIT_TAG" ]; then
    if [[ "$ENVIRONMENT" == "prod" ]]; then
      # checkout tag
      # Grab latest sprint TAG
      GIT_CHECKOUT=$(git_query tag | cut -d'/' -f3 | grep 'sprint' | sort -rV | head -n1)
      [ -z "$GIT_CHECKOUT" ] && GIT_CHECKOUT=$(git_query tag | cut -d'/' -f3 | grep 'release' | sort -rV | head -n1) # temporary hack until migration complete
      [ -z "$GIT_CHECKOUT" ] && die "ERROR: could not find latest sprint or release tag!"
    else
      # checkout branch
      # Failing all above, we try to checkout the latest BRANCH else fallback to master
      FINAL_CHECKOUT_TYPE="branch"
      GIT_CHECKOUT=$(git_query branch | cut -d'/' -f3 | grep 'sprint' | sort -rV | head -n1)
      [ -z "$GIT_CHECKOUT" ] && GIT_CHECKOUT=$(git_query branch | cut -d'/' -f3 | grep 'release' | sort -rV | head -n1)
      [ -z "$GIT_CHECKOUT" ] && GIT_CHECKOUT="master"
    fi
  else
    GIT_CHECKOUT="$GIT_TAG"
  fi
  echo "INFO: Checking out $FINAL_CHECKOUT_TYPE: $GIT_CHECKOUT"
}

execute_sql () {
  project="$1"
  sql_file="$2"
	# assumes we're sudo'ing and running as ***REMOVED***
  HOME="/***REMOVED***"
	mysql --default-character-set=utf8 --show-warnings < "${project}-${sql_file}" 2>&1 || die "ERROR: error executing sql commands"
}

get_sql_files () {
  project="$1"

  ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && \
  git archive --remote=git@${GITLAB_BASE}:${NAMESPACE}/${project}.git ${GIT_CHECKOUT}:${DB_PATH} \
  --format=tar ${DB_FILE} --prefix=${project}- | tar xf - " || die "ERROR: could not download $project ${DB_FILE} sql file"

  execute_sql "$project" "$DB_FILE"
}

### MAIN ###
cd "$WORK_DIR"
configure_checkout_type
get_sql_files "${PROJECT}"



# CLEANUP
cd /tmp
rm -rf "$WORK_DIR"

# EXIT
exit 0