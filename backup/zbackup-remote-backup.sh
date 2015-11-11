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
SAVEIFS=$IFS

DEBUG="FALSE"
SSH_USER="rundeck"
SSH_OPTIONS="-o StrictHostKeyChecking=no"
REMOTE_SERVER=""
ZB_REPOS_BASE="/srv/r5/backups/zbackup-repos"
ZB_JOBS="/***REMOVED***/scripts/zbackup-remote-backup-jobs.csv"
#ZB_JOBS="/***REMOVED***/scripts/debug.csv"
ZB_KEY="/***REMOVED***/keys/zbackup"
DIRECTORIES="ZB_REPOS_BASE ZB_JOBS ZB_KEY"

# Prepare our remote commands function
rc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_SERVER} "sudo sh -c '$@'" < /dev/null || { die "ERROR: Failed executing - $@ - on ${REMOTE_SERVER}"; }
}

# rc without dying
rcc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_SERVER} "sudo sh -c '$@'"  < /dev/null
}

# validate directories
# ensure directories and files exist
for directory in $DIRECTORIES; do
	[ -e "${!directory}" ] || die "ERROR: $directory can not be found."
done

IFS=','

sed 1d "$ZB_JOBS" | while read REMOTE_IP REMOTE_SOURCE_DIRS TAR_DIR APP REMOTE_TMPDIR ZB_REPO_NAME PRE_COMMANDS POST_COMMANDS;
do
	if [ "$DEBUG" = "TRUE" ];
	then
		SSH_USER="***REMOVED***" # (requires Defaults:***REMOVED*** !requiretty on destination sudoers config)
		ZB_JOBS="/***REMOVED***/scripts/test.job"
	fi

	echo "Remote IP: $REMOTE_IP"
	echo "Remote dirs: $REMOTE_SOURCE_DIRS"
	echo "Tar directory: $TAR_DIR"
	echo "App Name: $APP"
	echo "Remote tmpdir: $REMOTE_TMPDIR"
	echo "zbackup repo: $ZB_REPO_NAME"
	echo "Pre-commands: $PRE_COMMANDS"
	echo "Post-commands: $POST_COMMANDS"
	echo "============================"

	REMOTE_SERVER="${REMOTE_IP}"

	echo "INFO: Backing up $APP..."
	# add condition for rundeck / commander server itself (can't ssh into itself)
	#
	#
	#

	# add check for zbackup binary
	rcc "test -x /usr/local/bin/zbackup" && ZB_BIN="/usr/local/bin/zbackup" || ZB_BIN="/bin/zbackup"
	rcc "test -x $ZB_BIN" || ZB_BIN="/usr/bin/zbackup" 

	# check tmpdir (working directory) exists
	rcc "test -d $REMOTE_TMPDIR" || rc "mkdir -p $REMOTE_TMPDIR"

	# rsync ZB info key and passfile
	echo "INFO: rsync keys..."
	rsync -ar -e "ssh" --rsync-path="sudo rsync" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/info" "${SSH_USER}@${REMOTE_SERVER}:${REMOTE_TMPDIR}"
	rsync -ar -e "ssh" --rsync-path="sudo rsync" "$ZB_KEY" "${SSH_USER}@${REMOTE_SERVER}:${REMOTE_TMPDIR}"


	# initialise zbackup repo if doesn't exist
	ZB_REPO_TMP="${REMOTE_TMPDIR}/zbtemp"
	if rcc "test ! -d $ZB_REPO_TMP";
	then
		echo "INFO: initialising zbackup repo..."
		rc "$ZB_BIN --password-file ${REMOTE_TMPDIR}/zbackup init $ZB_REPO_TMP"
	fi

	# symlink the info file into the repo
	rc "ln -snf ${REMOTE_TMPDIR}/info ${ZB_REPO_TMP}/"

	# rsync zbackup indexes
	echo "INFO: rsync index..."
	rsync -ar -e "ssh" --rsync-path="sudo rsync" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/index" "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/"
              
	# pre-commands - before zbackup
	echo "INFO: running pre-commands - $PRE_COMMANDS..."
	[ ! -z "$PRE_COMMANDS" ] && rc "$PRE_COMMANDS"
	
	# zbackup
	FILE_DATE=$(date +%Y-%m-%d)
	BACKUP_FILE="${ZB_REPO_TMP}/backups/${APP}-${FILE_DATE}.tar"
	echo "INFO: creating zbackup..."
	if [ "$TAR_DIR" = "yes" ]
	then
		# backup some known directories / files
		rc "tar c $REMOTE_SOURCE_DIRS | $ZB_BIN --password-file ${REMOTE_TMPDIR}/zbackup backup $BACKUP_FILE" &>/dev/null
	else
		# backup latest backup triggered by pre-command(s), ideally all tar'd in one file
		# $REMOTE_SOURCE_DIRS should be ONE directory
		FILE=$(rcc "find $REMOTE_SOURCE_DIRS" | tail -n 1)
		echo "INFO: Backing up file - $FILE"
		if echo "$FILE" | grep -q "No such file or directory"; then die "ERROR: $FILE could not be found"; fi
		if [ -z "$FILE" ]; then die "ERROR: $FILE could not be found"; fi
        
        # check file and amend if not tar
        if [[ ${FILE: -3} != "tar" ]]; then
            BACKUP_FILE="${BACKUP_FILE:0:-3}${FILE: -3}"
        fi

        # create our backup of the file
		rc "cat $FILE | $ZB_BIN --password-file ${REMOTE_TMPDIR}/zbackup backup $BACKUP_FILE" &>/dev/null
	fi		

	# rsync new data to main backup server
	echo "INFO: rsync data up to backup server..."
	rsync -avr -e "ssh" --rsync-path="sudo rsync" "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/backups/" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/backups/${APP}/daily" || die "ERROR: Failed to rsync backup dir"
	rsync -avr -e "ssh" --rsync-path="sudo rsync" "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/bundles/" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/bundles" || die "ERROR: Failed to rsync bundles dir"
	rsync -avr -e "ssh" --rsync-path="sudo rsync" "${SSH_USER}@${REMOTE_SERVER}:${ZB_REPO_TMP}/index/" "${ZB_REPOS_BASE}/${ZB_REPO_NAME}/index" || die "ERROR: Failed to rsync index dir"
	
	# post-commands - after zbackup
	echo "INFO: running post-commands- $POST_COMMANDS..."
	[ ! -z "$POST_COMMANDS" ] && rc "$POST_COMMANDS"

	# clear backup and bundles dir from zbackup temporary repo - zbtemp
	# but keep the structure so we don't have to re-initialise the repo again
	echo "INFO: deleting backup and bundles on source..."
	rc "rm -f $BACKUP_FILE"
	rc "rm -rf ${ZB_REPO_TMP}/bundles/*"
	rc "rm -rf ${ZB_REPO_TMP}/index/*"

	# shred keys (redundant to do if multiple jobs exist on same server but very small price for safety)
	echo "INFO: shredding sensitive files..."
	rc "shred -u ${REMOTE_TMPDIR}/info"
	rc "shred -u ${REMOTE_TMPDIR}/zbackup"
	echo "INFO: Finished backing up $APP"
	echo "==============================="
done
