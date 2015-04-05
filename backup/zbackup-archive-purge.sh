#!/bin/bash

<<-"INTRO"
for each repo and for each backup / app in the repo:
copy the latest daily from daily directory to weekly and monthly
then purge old backups in daily and weekly according to retention
policy.

RETENTION POLICY
    full backup every 6h, keep for 3 days -> 12
    full backup every day, keep for 8 days
    full backup every week, Sunday, keep for 8 weeks 
    full backup every month, upload to ovh also
INTRO


die() 
{ 
	echo $* 1>&2
	#echo "$*" | mail -s "Backup - archive, rotate, purge issue: $*" ***REMOVED***@***REMOVED***.com
	exit 1 
}

# SETTINGS
DIR=$(cd "$(dirname "$0")" && pwd)
ZBACKUP_REPOS_BASE="/srv/r5/backups/zbackup-repos"
DATE=$(date +%Y-%m-%d)
ZB_LOCKS[0]="/var/run/zbackup-intranet-db"
RP_DAILY=8
RP_WEEKLY=8

# Ensure there are no zbackup jobs running
#for LOCK in "${ZB_LOCKS[@]}"
#do
#    echo "INFO: checking for locks - $LOCK"
#    [ -e "$LOCK" ] && die "ERROR: Lock - $LOCK found, exiting."
#done

# Ensure zbackup repos base exists
#[ -d "$ZBACKUP_REPOS_BASE" ] || die "ERROR: zbackup repo base not found - $ZBACKUP_REPOS_BASE"

copy_backup()
{
    FOLDER="$1"
    cd "$ZBACKUP_REPOS_BASE"
    for REPO in $(ls)
    do
        echo "INFO: zbackup repo = $REPO"
        REPO_BASE="${REPO}/backups"
        [ -d "$REPO_BASE" ] && cd "$REPO_BASE" || die "ERROR: could not find $REPO_BASE"
        for APP in $(ls)
        do
            cd "${APP}/daily"
            # cp last / latest backup into ../[daily|weekly] folder
            LATEST=$(ls -tr1 | tail -n 1)
            echo "INFO: copying $APP - $LATEST to ../${FOLDER} ..."
            cp -f "$LATEST" "../${FOLDER}"
            cd "${ZBACKUP_REPOS_BASE}/${REPO_BASE}"
        done
        cd "$ZBACKUP_REPOS_BASE"
    done
    echo "INFO: successfully created $FOLDER zbackups"
}

if [[ "$1" == "weekly" || "$1" == "monthly" ]]
then
    copy_backup "$1"
    # ovh archive
else
    die "ERROR: invalid argument"
fi

exit 0
