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


# VALIDATE
## Validate package managed tools
for TOOL in $TOOLS; do
  which $TOOL &>/dev/null || die "ERROR: $TOOL is not installed"
done

## Validate custom tools
[ -e /usr/local/bin/jq ] || { wget -O /usr/local/bin/jq http://stedolan.github.io/jq/download/linux64/jq && chmod +x /usr/local/bin/jq; }


# FUNCTIONS
execute_sql () {
  project="$1"
  sql_file="$2"
	# assumes we're sudo'ing and running as ***REMOVED***
  HOME="/***REMOVED***"
	mysql --default-character-set=utf8 --show-warnings < "${project}-${sql_file}" || die "ERROR: error executing sql commands"
}

get_sql_files () {
  project="$1"

  ssh-agent bash -c "ssh-add $DEPLOY_KEY &>/dev/null && \
  git archive --remote=git@${GITLAB_BASE}:${NAMESPACE}/${project}.git ${GIT_TAG}:${DB_PATH} \
  --format=tar ${DB_FILE} --prefix=${project}- | tar xf - " || die "ERROR: could not download $project ${DB_FILE} sql file"


  # debug
  #ls -la
  #[ -e "${project}-${DB_FILE}" ] || die "ERROR: Could not find sql file"

  #execute_sql "$project" "$DB_FILE"
}

### MAIN ###
cd "$WORK_DIR"
get_sql_files "${PROJECT}"



# CLEANUP
cd /tmp
rm -rf "$WORK_DIR"

# EXIT
exit 0