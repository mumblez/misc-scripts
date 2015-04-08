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
	echo "$*" | mail -s "Remote Backup Issue: $*" ***REMOVED***@***REMOVED***.com
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

DEBUG="FALSE"
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


DEBUG="TRUE"

IFS=',';
sed 1d "$ZB_JOBS" | while read REMOTE_IP REMOTE_SOURCE_DIRS TAR_DIR APP REMOTE_TMPDIR ZB_REPO_NAME PRE_COMMANDS POST_COMMANDS;
do
	if [ "DEBUG" = "TRUE"];
	then
		echo "Remote IP: $REMOTE_IP"
		echo "Remote dirs: $REMOTE_SOURCE_DIRS"
		echo "Tar directory: $TAR_DIR"
		echo "App Name: $APP"
		echo "Remote tmpdir: $REMOTE_TMPDIR"
		echo "zbackup repo: $ZB_REPO_NAME"
		echo "Pre-commands: $PRE_COMMANDS"
		echo "Post-commands: $POST_COMMANDS"
		echo "============================"
	fi

	REMOTE_SERVER="${REMOTE_IP}"

	# check tmpdir (working directory) exists
	rc test -d "$REMOTE_TMPDIR" || rc "mkdir -p $REMOTE_TMPDIR"

	# rsync ZB info key and passfile
	rsync -ar "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/info" "${SSH_USER}@${REMOTE_SERVER}:${REMOTE_TMPDIR}"
	rsync -ar "$ZB_KEY" "${SSH_USER}@${REMOTE_SERVER}:${REMOTE_TMPDIR}"


	# initialise zbackup repo if doesn't exist
	ZB_REPO_TMP="${REMOTE_TMPDIR}/zbtemp"
	if test ! -d "$ZB_REPO_TMP";
	then
		rc "zbackup --password-file ${REMOTE_TMPDIR}/zbackup init $ZB_REPO_TMP"
	fi

	# symlink the info file into the repo
	rc "ln -snf ${REMOTE_TMPDIR}/info ${ZB_REPO_TMP}/"

	# rsync indexes
	rsync -ar "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/index" "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/"

	# pre-commands
	[ ! -z "$PRE_COMMANDS" ] && rc "$PRE_COMMANDS"
	
	# zbackup
	rc "tar c $REMOTE_SOURCE_DIRS | zbackup --password-file ${REMOTE_TMPDIR}/zbackup backup ${ZB_REPO_TMP}/backups/"

	# rsync new data back
	rsync -ar "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/backups/" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/backups/${APP}/daily" || die "ERROR: Failed to rsync backup dir"
	rsync -ar "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/bundles/" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/bundles" || die "ERROR: Failed to rsync bundles dir"
	rsync -ar "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/index/" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/index" || die "ERROR: Failed to rsync index dir"
	
	# post-commands
	[ ! -z "$POST_COMMANDS" ] && rc "$POST_COMMANDS"

	# shred keys (redundant to do if multiple jobs exist on same server but very small price for safety)
	rc "shred -u ${REMOTE_TMPDIR}/info"
	rc "shred -u ${REMOTE_TMPDIR}/zbackup"
done