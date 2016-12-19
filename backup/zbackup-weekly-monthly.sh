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

Daily purges will be done in the originating backup scripts
Weekly purges will be done by this script when called by cron
INTRO


die()
{
	echo $* 1>&2
	#echo "$*" | mail -s "Backup - archive, rotate, purge issue: $*" someone@company.com
	exit 1
}

# SETTINGS
DIR=$(cd "$(dirname "$0")" && pwd)
ZBACKUP_REPOS_BASE="/srv/r5/backups/zbackup-repos"
DATE=$(date +%Y-%m-%d)
ZB_LOCKS[0]="/var/run/zbackup-intranet-db"
RP_WEEKLY=8
RP_DAILY=14

# Ensure there are no zbackup jobs running
for LOCK in "${ZB_LOCKS[@]}"
do
    echo "INFO: checking for locks - $LOCK"
    [ -e "$LOCK" ] && die "ERROR: Lock - $LOCK found, exiting."
done

# Ensure zbackup repos base exists
[ -d "$ZBACKUP_REPOS_BASE" ] || die "ERROR: zbackup repo base not found - $ZBACKUP_REPOS_BASE"

delete_old_backups()
{
    if [ "$(ls -1 | wc -l)" -gt "$1" ]; then
        for OLD_BAK in $(diff <(ls -1 | tail -n "$1") <(ls -1) | sed '1d' | awk '{print $2}');
        do
            [ ! -z "$OLD_BAK" ] && rm -rf "$OLD_BAK" && echo "INFO: Deleted $FOLDER - $APP - $OLD_BAK - `date`"
        done
    fi
}

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
	    # purge old dailies
	    delete_old_backups "$RP_DAILY"

            # cp last / latest backup into ../[daily|weekly] folder
            LATEST=$(ls -tr1 | tail -n 1)
            echo "INFO: copying $APP - $LATEST to ../${FOLDER} ..."
            cp -f "$LATEST" "../${FOLDER}"
            # purge old backups if weekly run#
            [[ "$FOLDER" == "weekly" ]] && cd ../weekly && delete_old_backups "$RP_WEEKLY"
            cd "${ZBACKUP_REPOS_BASE}/${REPO_BASE}"
            # for monthly purge, need to implement!
            # clone repo
            # delete weekly and daily dir's from each app
            # keep latest 6 months and archive 6 months
            # zbackup gc on repo
            # upload to ovh - do in 2016 after May's monthly!!!
        done
        cd "$ZBACKUP_REPOS_BASE"
    done
    echo "INFO: successfully created $FOLDER zbackups"
}

# main
if [[ "$1" == "weekly" || "$1" == "monthly" ]]
then
    copy_backup "$1"
    # ovh archive
else
    die "ERROR: invalid argument! ./${0} [weekly|monthly]"
fi

exit 0
