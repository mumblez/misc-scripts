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

ZB_REPOS_BASE="/srv/r5/backups/zbackup-repos"
ZB_JOBS="${DIR}/zbackup-remote-backup-jobs.csv"



# Prepare our remote commands function
rc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_DB_SERVER} "sudo $@" || { die "ERROR: Failed executing - $@ - on ${REMOTE_DB_SERVER}"; }
}

# rc without dying
rcc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_DB_SERVER} "sudo $@"
}


IFS=',';
sed 1d "$ZB_JOBS" | while read REMOTE_IP REMOTE_SOURCE_DIRS TAR_DIR APP REMOTE_TMPDIR ZB_REPO_NAME PRE_COMMANDS POST_COMMANDS;
do
	echo "Remote IP: $REMOTE_IP"
	echo "Remote dirs: $REMOTE_SOURCE_DIRS"
	echo "Tar directory: $TAR_DIR"
	echo "App Name: $APP"
	echo "Remote tmpdir: $REMOTE_TMPDIR"
	echo "zbackup repo: $ZB_REPO_NAME"
	echo "Pre-commands: $PRE_COMMANDS"
	echo "Post-commands: $POST_COMMANDS"
	echo "============================"
done