#!/bin/bash

# RD job to deploy legacy offspring / php 5.2 applications
# UUID: 9c3be6ff-f5f5-4aaa-b34e-e4bf6df389cf
# Path: https://***REMOVED***.***REMOVED***.com/project/Everything/jobs/snippets/misc/deployments/phase1
# Job name: Deploy Offspring Application - POC


die() { echo $* 1>&2 ; exit 1 ; }

# SETTINGS
START_TIME=$(date +%s)
ENVIRONMENT="@option.environment@"
DB_FILE_INTRANET="@option.db_file_intranet@"
DB_FILE_WEBSITE="@option.db_file_website@"
EVENTLOGTRIGGERS="@option.eventlogtriggers@"  # run always if non prod else check this value
HOST_BUILD="@option.host_build@"
HOST_REPO="@option.host_repo@"
UAT_FE="@option.uat_frontend@"
PROJECTS="@option.projects@"
TAG="@option.tag@"
SVN2GIT="@option.svn2git@"
# Rundeck job uuid references
JOB_BUILD_PKG="f41a878b-d2e5-4323-83ca-7dcd844a604d"
JOB_UPDATE_REPO="4aa08aad-4b62-4b97-9417-daf377a0c2e2"
JOB_INSTALL_PKG="2a8a37a3-3186-40ed-b916-28834e3e39a3"
JOB_SQL_EXEC="84425e20-1d3c-4a72-b38f-b9adda5cc685" # For intranet and/or website
JOB_EVENTLOGTRIGGER_GEN="fc803349-bbbf-4924-8618-7eb5d3f62518"
JOB_EVENTLOGTRIGGER_XFER="1b58f880-6c07-46c4-84c7-53525e008e06"
JOB_EVENTLOGTRIGGER_RUN="bb2c2b76-4901-46f0-9719-6a17184a058b"
JOB_SVN2GIT="876850e5-0646-4a27-8e0d-4b3d9ec99cac"
JOB_SERVICE_RESTART="abdc55a5-5c66-487b-b9f2-6286d50490bd"


## Mappings - front (web) and back (db) ends
#case "$ENVIRONMENT" in
#	qa )
#		HOST_WEB="qa-fe.dev.***REMOVED***.com"
#		HOST_DB="qa-db.dev.***REMOVED***.com"
#		;;
#	uat )
#		HOST_WEB="uat-fe${UAT_FE}.dev.***REMOVED***.com"
#		HOST_DB="uat-db1.dev.***REMOVED***.com"  # hard coded for now, but later generalise as 'uat-db' and change reference in hosts file
#		;;
#	test )
#		HOST_WEB="***REMOVED***.uk.***REMOVED***.com" # replace when DNS project implemented!!!!
#		HOST_DB="335298-db1.uk.***REMOVED***.com"
#		;;
#	training )
#		HOST_WEB="intranet-training-web1-uk-cl" # replace when DNS project implemented!!!!
#		HOST_DB="intranet-training-db-uk-cl"
#		;;
#	#prod )
#	#	HOST_WEB="335296-web1.uk.***REMOVED***.com" # #replace when DNS project implemented!!!!
#	#	HOST_DB="510094-db4.uk.***REMOVED***.com"
#	#	;;
#esac

# Mappings - front (web) and back (db) ends
case "$ENVIRONMENT" in
	qa )
		HOST_WEB="qweb1-lnov"
		HOST_DB="qdb1-lnov"
		;;
	uat )
		HOST_WEB="uweb${UAT_FE}-lnov"
		HOST_DB="udb1-lnov"  # hard coded for now, but later generalise as 'uat-db' and change reference in hosts file
		;;
	test )
		HOST_WEB="web2-lndp"
		HOST_DB="db1-lndp"
		;;
	training )
		HOST_WEB="trintranet-web1-lncv"
		HOST_DB="trintranet-db1-lncv"
		;;
	#prod )
	#	HOST_WEB="335296-web1.uk.***REMOVED***.com" # replace when DNS project implemented!!!!
	#	HOST_DB="510094-db4.uk.***REMOVED***.com"
	#	HOST_WEB="web1-lndp"
	#	HOST_DB="db4-lndp"
	#	;;
esac

if [[ "$SVN2GIT" == "yes" ]]; then
	echo "INFO: Converting and updating git repositories from SVN..."
	run -i "$JOB_SVN2GIT" -f
fi
[ "$?" != 0 ] && die "ERROR: Error with svn 2 git conversion!"


echo "INFO: Deploying for environment $ENVIRONMENT"

# Build debian packages from source (pass in list of projects)
# if no tag passed in then it builds 
run -i "$JOB_BUILD_PKG" -f -- \
	-environment "$ENVIRONMENT" \
	-host "$HOST_BUILD" \
	-projects "$PROJECTS" \
	-tag "$TAG"

[ "$?" != 0 ] && die "ERROR: Error building packages!"
echo "INFO: Successfully built packages"

# Update package repository listing (only need to run once after all packages have been built)
run -i "$JOB_UPDATE_REPO" -f -- -environment "$ENVIRONMENT" -host "$HOST_REPO"

[ "$?" != 0 ] && die "ERROR: Error updating debian package repository"
echo "INFO: Successfully updated debian package repository"

# Install packages on front ends (pass in list of projects)
run -i "$JOB_INSTALL_PKG" -f -- -host "$HOST_WEB" -projects "$PROJECTS"

[ "$?" != 0 ] && die "ERROR: Error installing debian package(s)"
echo "INFO: Succesfully installed debian package(s)"

run -i "$JOB_SERVICE_RESTART" -f -- -host "$HOST_WEB" -service "php52-fpm"
[ "$?" != 0 ] && die "ERROR: restarting php52-fpm service"
run -i "$JOB_SERVICE_RESTART" -f -- -host "$HOST_WEB" -service "apache2"
[ "$?" != 0 ] && die "ERROR: restarting apache2 service"
echo "INFO: Successfully restarted apache and php-fpm services."

# Set permissions on /***REMOVED*** - hack until can figure out where offspring logs gets its permissions from
ssh -o StrictHostKeyChecking=no rundeck@${HOST_WEB} sudo chown www-data:www-data /***REMOVED*** -R
[ "$?" != 0 ] && die "ERROR: resetting /***REMOVED*** directory permissions"
echo "INFO: Succesfully reset /***REMOVED*** directory permissions"

# Run sql / db_files for intranet and website
sql_exec_run() {
	run -i "$JOB_SQL_EXEC" -f -- \
	-host "$HOST_DB" \
	-db_file "$2" \
	-project "$1" \
	-environment "$ENVIRONMENT" \
	-tag "$TAG"

	[ "$?" != 0 ] && die "ERROR: Error running sql file for $1"
}

for project in $PROJECTS; do
	case "$project" in
		intranet )	sql_exec_run "$project" "$DB_FILE_INTRANET"	;;
		website )	sql_exec_run "$project" "$DB_FILE_WEBSITE" ;;
	esac
done

echo "INFO: Successfully run sql file for intranet / website project(s)"

# Execute eventLogTriggers sql

if [[ "$EVENTLOGTRIGGERS" == "yes" ]]; then
	run -i "$JOB_EVENTLOGTRIGGER_GEN" -f -- -host "$HOST_WEB"
	run -i "$JOB_EVENTLOGTRIGGER_XFER" -f -- -web_frontend "$HOST_WEB" -db_backend "$HOST_DB"
	run -i "$JOB_EVENTLOGTRIGGER_RUN" -f -- -host "$HOST_DB"
fi

[ "$?" != 0 ] && die "ERROR: Error running eventlogtriggers"
echo "INFO: Successfully run eventlogtriggers"

# change Intranet version file to sprint tag?
# echo "Creating VERSION file";
# REVISION=`svn info /opt/jenkins/jobs/intranet/workspace/ 2>/dev/null | grep ^Revision | awk '{print $2}'`;
# ssh ***REMOVED***@qa-fe "echo 'BUILD=$REVISION' > /***REMOVED***/config/intranet/version"


echo "INFO: Started - $(date -d @$START_TIME)"
END_TIME=$(date +%s)
echo "INFO: Ended   - $(date -d @$END_TIME)"
echo "INFO: Duration - $(date -u -d @$(($END_TIME - $START_TIME)) +%T)"
echo "INFO: Deployment Succeeded!"