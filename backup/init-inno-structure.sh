#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
#LOG="${DIR}/init-inno.log"
#touch "$LOG"
#chmod 777 "$LOG"
#exec > >("$LOG")
#exec 2>&1

LOG_BASE="/var/log/innobackupex"
LOG_INCREMENTAL="${LOG_BASE}/incremental-backup.log"
LOG_FULL="${LOG_BASE}/full-backup.log"
CRON="/etc/cron.d/intranet-db"
IBI_LOCK="/var/run/dbbackup"
ZB_LOCK="/var/run/zbackup-intranet-db"
BACKUP_SCRIPT="/***REMOVED***/scripts/mysql-backup.sh"

# delete cron to stop jobs
[ -e "$CRON" ] && rm -f "$CRON"

if [ -e $IBI_LOCK -o -e $ZB_LOCK ]; then
	echo "Backups are in progress, either kill them or try again later!"
fi

[ -e "$BACKUP_SCRIPT" ] || { echo "ERROR: could not find backup script - $BACKUP_SCRIPT"; exit 1; }

# create the first backup and checkpoint directory
innobackupex --safe-slave-backup --slave-info --no-timestamp --extra-lsndir ${DIR}/last-checkpoint ${DIR}/hotcopy

# apply log ready for incrementals
innobackupex --apply-log --redo-only ${DIR}/hotcopy

# create incrementals base dir
mkdir ${DIR}/incrementals

# symlink to /var/log
ln -snf "$LOG_BASE" logs

# create realised directory
#cp -ar ${DIR}/hotcopy ${DIR}/realised

# make our cron

if which dogwrap &>/dev/null; then
cat > $CRON <<_EOF_
MAILTO=""
# mysql backup - intranet
# incremental
00 5,11,17,23 * * *     ***REMOVED***     dogwrap -n "DB - CL-WEB - incremental backup" -k \$(cat /***REMOVED***/keys/datadogapi) --submit_mode all "/***REMOVED***/scripts/mysql-backup.sh incremental"
# full
25 23 * * *     ***REMOVED***    dogwrap -n "DB - CL-WEB - full backup" -k \$(cat /***REMOVED***/keys/datadogapi) --submit_mode all "/***REMOVED***/scripts/mysql-backup.sh full"
_EOF_

else
cat > $CRON <<_EOF_
MAILTO=""
# mysql backup - intranet
# incremental
00 5,11,17,23 * * *	***REMOVED***	$BACKUP_SCRIPT incremental &>/dev/null
# full
30 23 * * *	***REMOVED***	$BACKUP_SCRIPT full &>/dev/null
_EOF_

fi

echo "Finished initialisation - `date`"

exit 0
