#!/bin/bash

# for use on rackspace dedicated backup server

die() 
{ 
	echo $* 1>&2
	echo "$*" | mail -s "DB Backup Issue: $*" ***REMOVED***@***REMOVED***.com
	exit 1 
}

# SETTINGS
IB_BASE="/srv/r5/backups/mysql-innobackupex"
ZBACKUP_BASE="/srv/r5/backups/zbackup-repo/backups/mysql/intranet"
ZB_KEY="/***REMOVED***/keys/zbackup"
INCREMENTALS_TO_KEEP="25"
IB_INCREMENTAL_BASE="${IB_BASE}/incrementals"
IB_CHECKPOINT="${IB_BASE}/last-checkpoint"
IB_HOTCOPY="${IB_BASE}/hotcopy"
REALISED_COPY="/srv/r5/backups/mysql-innobackupex/realised"
DATE=$(date +%Y-%m-%d)
DIR=$(cd "$(dirname "$0")" && pwd)
IBI_LOCK="/var/run/dbbackup"
ZB_LOCK="/var/run/zbackup"
ZB_LOG="/var/log/zbackup/mysql-full-backup.log"
TOOLS="zbackup innobackupex"
DIRECTORIES="IB_BASE ZBACKUP_BASE IB_INCREMENTAL_BASE IB_CHECKPOINT IB_HOTCOPY"



# mysql backups with innobackupex and zbackup
# initial setup, create backup, apply-log and redo-log and make copy, 1 copy = hotcopy, 1 = realised
# also create zbackup
# realised = most current backup with all incrementals applied - for fast recovery
# - every hour run an incremental
# -- roll latest (3rd to last) incremental into realised (gives us 2hr fallback)
# - keep last 24 incrementals or 2 days worth
#
#
# roll in the days incrementals
# @11 find all incrementals with same date
# roll in incrementals and verify with xtradb_checkpoints (to_lsn and from_lsn should match)
# then verify last line output = "completed OK!"


#full backup with rollup
#while loop on lock so last incremental can finish
#-validate checkpoints
#-touch lock???
#-roll in with apply-log and redo-only
#-validate complete OK!
#-continue with next folder
#for loop and check checkpoints file until last checkpoint not found
#-remove lock
#call zbackup and create a lock (general zbackup lock for all future backups)
#
#any restores require apply-log


# ensure user passes in argument of either full or incremental
if [ $# -lt 1 ]; then
	die "ERROR: you need to pass in an argument - [full|incremental]"
fi

# ensure tools exist
for tool in $TOOLS; do
	which $tool &> /dev/null || die "ERROR: $tool is not available on the system."
done

# ensure directories and files exist
for directory in $DIRECTORIES; do
	[ -d "${!directory}" ] || die "ERROR: $directory can not be found."
done


ibi_lock_check()
{
	[ -e $IBI_LOCK ] && die "ERROR: `date` - Backup job still running, remove $IBI_LOCK if not true."
}


incremental_backup()
{
	ibi_lock_check
	touch "$IBI_LOCK"
	INC_APPLY_LOG="/tmp/inc_apply_realised.log"
	echo "### Starting incremental: $(date) ###"
	INCREMENTAL_DATE=$(date +%Y-%m-%d)
	# create incremental
	innobackupex --incremental \
	--extra-lsndir "$IB_CHECKPOINT" \
	--safe-slave-backup \
	--slave-info \
	--incremental-basedir "$IB_CHECKPOINT" \
	"$IB_INCREMENTAL_BASE" &> "$INC_APPLY_LOG"

	# check it completed successfully
	if tail -n 1 "$INC_APPLY_LOG" | grep -q 'innobackupex: completed OK!'; then 
		echo "INFO: incremental backup successful - `date`"
		rm -f "$INC_APPLY_LOG"
	else
		die "ERROR: incremental backup failed - `date`"
	fi

	# roll into realised directory, always 3rd from last
	## save realised checkpoint
	REALISED_CHECKPOINT=$(cat "${REALISED_COPY}/xtrabackup_checkpoints" | awk '/^to_lsn/ {print $3}')
	## find incremental with matching checkpoint and ensure it's 2nd to last
	INCREMENTAL_TMP=$(ls -1 "$IB_INCREMENTAL_BASE" | tail -n 3 | head -n 1)
	INCREMENTAL_CURRENT="${IB_INCREMENTAL_BASE}/${INCREMENTAL_TMP}"
	INC_CHECKPOINT=$(cat "${INCREMENTAL_CURRENT}/xtrabackup_checkpoints" | awk '/^from_lsn/ {print $3}')

	if [ "$INC_CHECKPOINT" -eq "$REALISED_CHECKPOINT" -a "$(ls -1 $IB_INCREMENTAL_BASE | wc -l)" -gt 2 ]; then
		innobackupex --apply-log --redo-only "$REALISED_COPY" --incremental-dir "$INCREMENTAL_CURRENT" &> "$INC_APPLY_LOG"

		if tail -n 1 "$INC_APPLY_LOG" | grep -q 'innobackupex: completed OK!'; then 
			echo "INFO: applying incremental successful - $INCREMENTAL_CURRENT - `date`"
			rm -f "$INC_APPLY_LOG"
		else
			die "ERROR: applying incremental failed - $INCREMENTAL_CURRENT - `date`"
		fi

	else
		echo "WARN: Checkpoints don't match for $INCREMENTAL_CURRENT, skip rolling in incremental"
	fi

	# Keep limited number of incrementals and delete old ones
	cd "$IB_INCREMENTAL_BASE"
	if [ "$(ls -1 | wc -l)" -gt "$INCREMENTALS_TO_KEEP" ]; then
		for OLD_INC in $(diff <(ls -1 | tail -n "$INCREMENTALS_TO_KEEP") <(ls -1) | sed '1d' | awk '{print $2}');
		do
			[ ! -z "$OLD_INC" ] && rm -rf "$OLD_INC" && echo "INFO: Deleted incremental - $OLD_INC - `date`"
		done
	fi

	rm -f "$IBI_LOCK"
	echo "### Finish incremental: $(date) ###"
}

full_backup()
{
	INCREMENTAL_DATE=$(date +%Y-%m-%d)
	# Let incremental finish if still running
	while [ -e $IBI_LOCK ]; do
		sleep 60;
	done
	
	[ -e $ZB_LOCK ] && die "ERROR: zbackup still running..."
	[ -e $ZB_KEY ] || die "ERROR: zbackup key file not found"

	echo "### Start rolling the days incrementals into hotcopy - $IB_HOTCOPY - $(date) ###"

	# find and roll in the days hourly incrementals
	INCREMENTAL_DIRS=$(find $IB_INCREMENTAL_BASE -maxdepth 1 -type d -name ${INCREMENTAL_DATE}_\* | sort -n)


	if [ -n "$INCREMENTAL_DIRS" ]; then
		# loop through and apply increments, will validate xtrabackup_checkpoints
		INC_COUNTER=1
		INC_APPLY_LOG="/tmp/inc_apply_hotcopy.log"
		for INCREMENTAL_DIR in $INCREMENTAL_DIRS; do
			# validate checkpoints
			HOTCOPY_CHECKPOINT=$(cat "${IB_HOTCOPY}/xtrabackup_checkpoints" | awk '/^to_lsn/ {print $3}')
			INC_CHECKPOINT=$(cat "${INCREMENTAL_DIR}/xtrabackup_checkpoints" | awk '/^from_lsn/ {print $3}')
			[ "$INC_CHECKPOINT" -ne "$HOTCOPY_CHECKPOINT" ] && die "ERROR: Checkpoints don't match for $INCREMENTAL_DIR"

			# start applying incrementals into the hotcopy
			echo "INFO: FULL - applying incremental - $INC_COUNTER ... - $INCREMENTAL_DIR - `date`"
			innobackupex --apply-log --redo-only "$IB_HOTCOPY" --incremental-dir "$INCREMENTAL_DIR" &> "$INC_APPLY_LOG"
			# validate completed successfully
			if tail -n 1 "$INC_APPLY_LOG" | grep -q 'innobackupex: completed OK!'; then 
				echo "INFO: FULL - applying incremental - $INC_COUNTER successful - $INCREMENTAL_DIR - `date`"
			else
				die "ERROR: FULL - applying incremental - $INC_COUNTER failed - $INCREMENTAL_DIR - `date`"
			fi
			INC_COUNTER=$(($INC_COUNTER+1))
			rm -f "$INC_APPLY_LOG"
		done

		echo "### Finished rolling the days incrementals into hotcopy - $IB_HOTCOPY - $(date) ###"
	else
		echo "WARN: No incremental backups found for today - $INCREMENTAL_DATE - inside $IB_INCREMENTAL_BASE"
	fi

	echo "### Start daily zbackup of $IB_HOTCOPY - $(date) ###"	

	[ -e "$ZB_LOCK" ] && die "ERROR: zbackup lock found, skiping zbackup backup"

	# Create zbackup of todays hotcopy
	touch $ZB_LOCK
	ZBACKUP_FILE="${ZBACKUP_BASE}/${INCREMENTAL_DATE}.tar"

	echo "INFO: `date` - running zbackup of $IB_HOTCOPY to $ZBACKUP_FILE..." | tee >> "$ZB_LOG"
	
	# run prepared hotcopy through zbackup
	tar -cf - -C "$IB_HOTCOPY" . | zbackup --password-file "$ZB_KEY" backup "$ZBACKUP_FILE" &>> "$ZB_LOG"

	echo "### Finished daily zbackup of $IB_HOTCOPY - $(date) ###"	
	rm -f "$ZB_LOCK"
}




# main

case $1 in
	incremental )
		incremental_backup
		;;
	full )
		full_backup
		;;
	*)
		die "ERROR: invalid argument! use [full|incremental]"
		;;
esac
