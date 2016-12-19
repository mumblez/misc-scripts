#!/bin/bash

### SETTINGS ###
die() { echo $* 1>&2 ; exit 1 ; }
TEMP_AREA=/tmp
WORK_DIR=$(mktemp -d $TEMP_AREA/sql_deploy.XXX)
REPO_PREFIX="somerepo@repo.com:prefix"
PROJECTS="@option.projects@"
RELEASE="@option.tag@"
#RELEASE_PREFIX="release-"
#GIT_TAG="${RELEASE_PREFIX}${RELEASE}"
RELEASE_ESCAPED=$(echo "$RELEASE" | sed -r 's/\./\\./g')
GITLAB_BASE="some.git.server"
NAMESPACE="somenamespace"
DEPLOY_TOKEN="someapikey" # API
DEPLOY_KEY="/root/keys/cl_deploy"   # GIT
DB_PATH="db"


# Validate
which git >/dev/null 2>&1 || die "ERROR: git client not installed"
which mysql >/dev/null 2>&1 || die "ERROR: mysql client not installed"
which mktemp >/dev/null 2>&1 || die "ERROR: mktemp is not installed"
which curl >/dev/null 2>&1 || die "ERROR: curl is not installed"
#[ -e /usr/local/bin/jq ] || die "ERROR: jq - json parsing tool missing (from /usr/local/bin)"
[ -e /usr/local/bin/jq ] || { wget -O /usr/local/bin/jq http://stedolan.github.io/jq/download/linux64/jq && chmod +x /usr/local/bin/jq; }
# http://stedolan.github.io/jq/download/linux64/jq
# assume /root/.my.cnf or /etc/mysql/deployment.cnf exists


# Functions
execute_sql () {
    project="$1"
	sql_file="$2"
	# assumes we're sudo'ing and running as root
	mysql < $project-$sql_file || die "ERROR: error executing sql commands"
}

get_sql_files () {
  project="$1"
  PROJECT_ID=$(curl --header "PRIVATE-TOKEN: $DEPLOY_TOKEN" -k -s \
    https://$GITLAB_BASE/api/v3/projects | \
    jq '.[] | {id,path_with_namespace}' | \
    grep $NAMESPACE/$project -A 1 | grep "id" | cut -d' ' -f 4)
  echo "ID: $PROJECT_ID for $project"

  # REWRITE TO USE TAGGED VERSION
  #SQL_FILE=$(curl --header "PRIVATE-TOKEN: $DEPLOY_TOKEN" -k -s \
  #	https://$GITLAB_BASE/api/v3/projects/$PROJECT_ID/repository/tree?path=db | \
 # 	jq '.[].name' | \
 # 	grep -oE "release-([0-9]{1,3}\.+){2}[0-9]{1,3}(-release)?-$RELEASE_ESCAPED.sql")

  # find file with pattern "release-<old version>-<new version>.sql"
  SQL_FILE=$(curl --header "PRIVATE-TOKEN: $DEPLOY_TOKEN" -k -s \
    https://$GITLAB_BASE/api/v3/projects/$PROJECT_ID/repository/tree?path=$DB_PATH | \
    jq -r '.[].name' | grep -oE "release-.*-$RELEASE.sql")
  echo "sql file: $SQL_FILE"
  [ ! -z "$SQL_FILE" ] || echo "WARN: $project sql file could not be found!!!!"

  # ENSURE FILE EXISTS BEFORE CONTINUEING

  if [ ! -z "$SQL_FILE" ]; then
    GIT_TAG=$(curl --header "PRIVATE-TOKEN: $DEPLOY_TOKEN" -k -s \
    https://$GITLAB_BASE/api/v3/projects/$PROJECT_ID/repository/tags | \
    jq -r '.[].name' | grep "$RELEASE")
  echo "GIT TAG: $GIT_TAG"
  ssh-agent bash -c "ssh-add $DEPLOY_KEY >/dev/null 2>&1 && \
    git archive --remote=git@"$GITLAB_BASE":"$NAMESPACE"/"$project".git "$GIT_TAG":"$DB_PATH" \
    --format=tar "$SQL_FILE" --prefix="$project"- | tar xf - " \
    || die "ERROR: could not download $project sql file"
  fi

  # Download with api since we're already using it
  # curl --header "PRIVATE-TOKEN: $DEPLOY_TOKEN" \
  #   -d ref="$GIT_TAG" \
  #   -d file_path="${DB_PATH}/${SQL_FILE}" \
  #   -k -s --request GET \
  #   https://$GITLAB_BASE/api/v3/projects/"$PROJECT_ID"/repository/files | \
  #   jq -r '.["content"]' | base64 -d > "$project-$SQL_FILE"
  ls -l *.sql
  #execute_sql "$project" "$SQL_FILE"
}

### MAIN ###
cd "$WORK_DIR"
for project in $PROJECTS; do
	get_sql_files $project
done

# Cleanup
rm -rf "$WORK_DIR"

# exit
exit 0
