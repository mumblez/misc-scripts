#!/bin/bash

<<INTRO
Via rundeck and ssh-agent for rundeck user on backup server, we will go OUT
to each server and backup the files, but do so via zbackup and transfer
only new bundles / data back to backup server.

The process is quite convaluted but will save us alot of space


INTRO

die() 
{ 
	echo $* 1>&2
#	echo "$*" | mail -s "Remote Backup Issue: $*" ***REMOVED***@***REMOVED***.com
	exit 1 
}

cleanup ()
{
	echo "INFO: Cleanup operations..."
	# clean up zbackup key

	# restore IFS
	IFS=$SAVEIFS;


}

trap cleanup EXIT

# SETTINGS
DIR=$(cd "$(dirname "$0")" && pwd)
SAVEIFS=$IFS;

DEBUG="TRUE"
SSH_USER="rundeck"
REMOTE_SERVER=""
ZB_REPOS_BASE="/srv/r5/backups/zbackup-repos"
ZB_JOBS="${DIR}/zbackup-remote-backup-jobs.csv"
ZB_KEY="/***REMOVED***/keys/zbackup"


# Prepare our remote commands function
rc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_SERVER} "sudo $@" || { die "ERROR: Failed executing - $@ - on ${REMOTE_SERVER}"; }
}

# rc without dying
rcc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_SERVER} "sudo $@"
}


DEBUG="FALSE"

IFS=',';

sed 1d "$ZB_JOBS" | while read REMOTE_IP REMOTE_SOURCE_DIRS TAR_DIR APP REMOTE_TMPDIR ZB_REPO_NAME PRE_COMMANDS POST_COMMANDS;
do
	if [ "$DEBUG" = "TRUE" ];
	then
		SSH_USER="***REMOVED***"
		ZB_JOBS="${DIR}/test.job"
		echo "Remote IP: $REMOTE_IP"
		echo "Remote dirs: $REMOTE_SOURCE_DIRS"
		echo "Tar directory: $TAR_DIR"
		echo "App Name: $APP"
		echo "Remote tmpdir: $REMOTE_TMPDIR"
		echo "zbackup repo: $ZB_REPO_NAME"
		echo "Pre-commands: $PRE_COMMANDS"
		echo "Post-commands: $POST_COMMANDS"
		echo "============================"
		set -x
	fi


	REMOTE_SERVER="${REMOTE_IP}"

	# check tmpdir (working directory) exists
	rcc "test -d $REMOTE_TMPDIR" || rc "mkdir -p $REMOTE_TMPDIR"

	# rsync ZB info key and passfile
	rsync -ar -e "ssh" --rsync-path="sudo rsync" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/info" "${SSH_USER}@${REMOTE_SERVER}:${REMOTE_TMPDIR}"
	rsync -ar -e "ssh" --rsync-path="sudo rsync" "$ZB_KEY" "${SSH_USER}@${REMOTE_SERVER}:${REMOTE_TMPDIR}"


	# initialise zbackup repo if doesn't exist
	ZB_REPO_TMP="${REMOTE_TMPDIR}/zbtemp"
	if rcc "test ! -d $ZB_REPO_TMP";
	then
		rc "zbackup --password-file ${REMOTE_TMPDIR}/zbackup init $ZB_REPO_TMP"
	fi

	# symlink the info file into the repo
	rc "ln -snf ${REMOTE_TMPDIR}/info ${ZB_REPO_TMP}/"

	# rsync indexes
	rsync -ar -e "ssh" --rsync-path="sudo rsync" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/index" "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/"
              
	# pre- commands
	[ ! -z "$PRE_COMMANDS" ] && rc "$PRE_COMMANDS"
	
	# zbackup
	FILE_DATE=$(date +%Y-%m-%d)
	BACKUP_FILE="${ZB_REPO_TMP}/backups/${APP}-${FILE_DATE}.tar"
	if [ "$TAR_DIR" = "YES" ]
	then
		rc "tar c $REMOTE_SOURCE_DIRS | zbackup --password-file ${REMOTE_TMPDIR}/zbackup backup $BACKUP_FILE"
	else
		FILE=$(rc "find $REMOTE_SOURCE_DIRS" | tail -n 1)
		rc "cat $FILE | sudo zbackup --password-file ${REMOTE_TMPDIR}/zbackup backup $BACKUP_FILE"
	fi		

	# rsync new data back
	rsync -ar -e "ssh" --rsync-path="sudo rsync" "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/backups/" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/backups/${APP}/daily" || die "ERROR: Failed to rsync backup dir"
	rsync -ar -e "ssh" --rsync-path="sudo rsync" "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/bundles/" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/bundles" || die "ERROR: Failed to rsync bundles dir"
	rsync -ar -e "ssh" --rsync-path="sudo rsync" "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/index/" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/index" || die "ERROR: Failed to rsync index dir"
	
	# post-commands
	[ ! -z "$POST_COMMANDS" ] && rc "$POST_COMMANDS"

	# clear backup and bundles dir from zbtemp
	rc "rm -f $BACKUP_FILE"
	rc "rm -rf ${ZB_REPO_TMP}/bundles/*"

	# shred keys (redundant to do if multiple jobs exist on same server but very small price for safety)
	rc "shred -u ${REMOTE_TMPDIR}/info"
	rc "shred -u ${REMOTE_TMPDIR}/zbackup"
done
