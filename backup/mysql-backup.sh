#!/bin/bash

# for use on rackspace dedicated backup server

if [ -n "$2" ]; then
	MANUAL_DATE="$2"
fi

die() 
{ 
	echo $* 1>&2
	echo "$*" | mail -s "DB Backup Issue: $*" ***REMOVED***@***REMOVED***.com
	exit 1 
}

# SETTINGS
IB_BASE="/srv/r5/backups/mysql-innobackupex"
ZBACKUP_BASE="/srv/r5/backups/zbackup-repo/backups/mysql/intranet/daily"
ZB_KEY="/***REMOVED***/keys/zbackup"
INCREMENTALS_TO_KEEP="13"
IB_INCREMENTAL_BASE="${IB_BASE}/incrementals"
IB_CHECKPOINT="${IB_BASE}/last-checkpoint"
IB_HOTCOPY="${IB_BASE}/hotcopy"
REALISED_COPY="/srv/r5/backups/mysql-innobackupex/realised"
DATE=$(date +%Y-%m-%d)
DIR=$(cd "$(dirname "$0")" && pwd)
IBI_LOCK="/var/run/dbbackup"
ZB_LOCK="/var/run/zbackup-intranet-db"
ZB_LOG="/var/log/zbackup/mysql-full-backup.log"
TOOLS="zbackup innobackupex"
DIRECTORIES="IB_BASE ZBACKUP_BASE IB_INCREMENTAL_BASE IB_CHECKPOINT IB_HOTCOPY"


# Instead of realised, hotcopy and incrementals (which seem to always fail when
# rolling in, we just create a full backup and 3 incrementals, it doesn't matter
# too much if the incrementals fail but a bonus if they work, a brand new
# full will be created every day and then 3 incrementals based on that (same date)
# 23:00 = full
# 05:00 = inc
# 11:00 = inc
# 17:00 = inc
# Full + zbackup, inc x3, attempt to roll in when next Full, if fail then
# run full again.

# In the event we do want to restore and try rolling in an incremental, we should
# make a copy of the full / hotcopy, just in case the incremental

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
	echo "-"
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

#	# roll into realised directory, always 3rd from last
#	## save realised checkpoint
#	REALISED_CHECKPOINT=$(cat "${REALISED_COPY}/xtrabackup_checkpoints" | awk '/^to_lsn/ {print $3}')
#	## find incremental with matching checkpoint and ensure it's 2nd to last
#	#INCREMENTAL_TMP=$(ls -1 "$IB_INCREMENTAL_BASE" | tail -n 3 | head -n 1)
#	INCREMENTAL_TMP=$(ls -1 "$IB_INCREMENTAL_BASE" | tail -n 1)
#	INCREMENTAL_CURRENT="${IB_INCREMENTAL_BASE}/${INCREMENTAL_TMP}"
#	INC_CHECKPOINT=$(cat "${INCREMENTAL_CURRENT}/xtrabackup_checkpoints" | awk '/^from_lsn/ {print $3}')
#
#	if [ "$INC_CHECKPOINT" -eq "$REALISED_CHECKPOINT" -a "$(ls -1 $IB_INCREMENTAL_BASE | wc -l)" -gt 2 ]; then
#		innobackupex --apply-log --redo-only \
#            "$REALISED_COPY" \
#            --incremental-dir "$INCREMENTAL_CURRENT" \
#            --use-memory=4GB \
#            &> "$INC_APPLY_LOG"
#
#		if tail -n 1 "$INC_APPLY_LOG" | grep -q 'innobackupex: completed OK!'; then 
#			echo "INFO: applying incremental successful - $INCREMENTAL_CURRENT - `date`"
#			rm -f "$INC_APPLY_LOG"
#		else
#			die "ERROR: applying incremental failed - $INCREMENTAL_CURRENT - `date`"
#		fi
#
#	else
#		echo "WARN: Checkpoints don't match for $INCREMENTAL_CURRENT, skip rolling in incremental"
#	fi

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
        # allow manually passing in the date as 2nd argument
        if [ -n "$MANUAL_DATE" ]; then
                INCREMENTAL_DATE="$MANUAL_DATE"
		echo "INFO: manual date passed in - $MANUAL_DATE <----------------------------------------"
        else
                INCREMENTAL_DATE=$(date +%Y-%m-%d)
        fi

	# Let incremental finish if still running
	while [ -e $IBI_LOCK ]; do
		sleep 60;
	done
	
	[ -e $ZB_LOCK ] && die "ERROR: zbackup still running..."
	[ -e $ZB_KEY ] || die "ERROR: zbackup key file not found"

	echo "-"
	echo "### Start rolling the days incrementals into hotcopy - $IB_HOTCOPY - $(date) ###"

	# find and roll in the days hourly incrementals
	INCREMENTAL_DIRS=$(find $IB_INCREMENTAL_BASE -maxdepth 1 -type d -name ${INCREMENTAL_DATE}_\* | sort -n)

    INC_APPLY_ERROR="no"

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
			innobackupex --apply-log --redo-only "$IB_HOTCOPY" \
                --incremental-dir "$INCREMENTAL_DIR" \
                --use-memory=4GB \
                &> "$INC_APPLY_LOG"
			# validate completed successfully
			if tail -n 1 "$INC_APPLY_LOG" | grep -q 'innobackupex: completed OK!'; then 
				echo "INFO: FULL - applying incremental - $INC_COUNTER successful - $INCREMENTAL_DIR - `date`"
			else
				echo "ERROR: FULL - applying incremental - $INC_COUNTER failed - $INCREMENTAL_DIR - `date`"
                # Trigger full backup + zbackup
                INC_APPLY_ERROR="yes"
                break
			fi
			INC_COUNTER=$(($INC_COUNTER+1))
			rm -f "$INC_APPLY_LOG"
			sleep 30
		done

        	if [ "$INC_APPLY_ERROR" = "no" ]; then
  		    echo "### Finished rolling the days incrementals into hotcopy - $IB_HOTCOPY - $(date) ###"
        	else
			rm -rf "$IB_HOTCOPY"
            		innobackupex --no-timestamp --extra-lsndir "$IB_CHECKPOINT" "$IB_HOTCOPY" &> "$INC_APPLY_LOG"
        		# check it completed successfully
        		if tail -n 1 "$INC_APPLY_LOG" | grep -q 'innobackupex: completed OK!'; then 
        			echo "INFO: FULL backup successful - `date`"
        			rm -f "$INC_APPLY_LOG"
        		else
        			die "ERROR: FULL backup failed - `date`"
        		fi
        	fi
	else
		echo "WARN: No incremental backups found for today - $INCREMENTAL_DATE - inside $IB_INCREMENTAL_BASE"
	fi

	echo "### Start daily zbackup of $IB_HOTCOPY - $(date) ###"	

	[ -e "$ZB_LOCK" ] && die "ERROR: zbackup lock found, skiping zbackup backup"

	# Create zbackup of todays hotcopy
	touch $ZB_LOCK
	ZBACKUP_FILE="${ZBACKUP_BASE}/${INCREMENTAL_DATE}.tar"
	[ -e "$ZBACKUP_FILE" ] && rm -f "$ZBACKUP_FILE" && "WARN: Found and deleted existing version of backup"

	echo "INFO: `date` - running zbackup of $IB_HOTCOPY to $ZBACKUP_FILE..." | tee >> "$ZB_LOG"
	
	# run prepared hotcopy through zbackup
	tar -cf - -C "$IB_HOTCOPY" . | zbackup --password-file "$ZB_KEY" backup "$ZBACKUP_FILE" &>> "$ZB_LOG"

	echo "### Finished daily zbackup of $IB_HOTCOPY - $(date) ###"	
	rm -f "$ZB_LOCK"
}




# main..

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
