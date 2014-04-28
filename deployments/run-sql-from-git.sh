#!/bin/bash

### SETTINGS ###
die() { echo $* 1>&2 ; exit 1 ; }
TEMP_AREA=/tmp
WORK_DIR=$(mktemp -d $TEMP_AREA/sql_deploy.XXX)
REPO_PREFIX="git@***REMOVED***.***REMOVED***.com:***REMOVED***"
PROJECTS="@option.projects@"
RELEASE="@option.tag@"
RELEASE_PREFIX="release-"
GIT_TAG="${RELEASE_PREFIX}${RELEASE}"
RELEASE_ESCAPED=$(echo "$RELEASE" | sed -r 's/\./\\./g')
GITLAB_BASE="***REMOVED***.***REMOVED***.com"
NAMESPACE="***REMOVED***"
DEPLOY_TOKEN="***REMOVED***"
DEPLOY_KEY="/***REMOVED***/keys/cl_deploy"


# Validate
which git >/dev/null 2>&1 || die "ERROR: git client not installed"
which mysql >/dev/null 2>&1 || die "ERROR: mysql client not installed"
which mktemp >/dev/null 2>&1 || die "ERROR: mktemp is not installed"
which curl >/dev/null 2>&1 || die "ERROR: curl is not installed"
[ -e /usr/local/bin/jq ] || die "ERROR: jq - json parsing tool missing (from /usr/local/bin)"
# http://stedolan.github.io/jq/download/linux64/jq
# assume /***REMOVED***/.my.cnf or /etc/mysql/deployment.cnf exists


# Functions
execute_sql () {
    project="$1"
  sql_file="$2"
  # assumes we're sudo'ing and running as ***REMOVED***
  mysql < $project-$sql_file || die "ERROR: error executing sql commands"
}

get_sql_files () {
  project="$1"
  PROJECT_ID=$(curl --header "PRIVATE-TOKEN: $DEPLOY_TOKEN" -k -s \
    https://$GITLAB_BASE/api/v3/projects | \
    jq '.[] | {id,path_with_namespace}' | \
    grep $NAMESPACE/$project -A 1 | grep "id" | cut -d' ' -f 4)
  echo "ID: $PROJECT_ID for $project"
  SQL_FILE=$(curl --header "PRIVATE-TOKEN: $DEPLOY_TOKEN" -k -s \
    https://$GITLAB_BASE/api/v3/projects/$PROJECT_ID/repository/tree?path=db | \
    jq '.[].name' | \
    grep -oE "release-([0-9]{1,3}\.+){2}[0-9]{1,3}(-release)?-$RELEASE_ESCAPED.sql")
  echo "$SQL_FILE"  
  ssh-agent bash -c "ssh-add $DEPLOY_KEY >/dev/null 2>&1 && \
    git archive --remote=git@"$GITLAB_BASE:$NAMESPACE/$project.git" "$GIT_TAG":db --format=tar $SQL_FILE --prefix="$project-" | tar xf - " \
  || die "ERROR: could not download $project sql file"
  #execute_sql "$project" "$SQL_FILE"
}

### MAIN ###
cd "$WORK_DIR"
for project in $PROJECTS; do
  get_sql_files $project
done

# Cleanup
#rm -rf "$WORK_DIR"

# exit
exit 0