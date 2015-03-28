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

[ -e "$BACKUP_SCRIPT" ] || { echo "ERROR: could not find backup script - $BACKUP_SCRIPT"; exit 1 }

# create the first backup and checkpoint directory
innobackupex --safe-slave-backup --slave-info --no-timestamp --extra-lsndir ${DIR}/last-checkpoint ${DIR}/hotcopy

# apply log ready for incrementals
innobackupex --apply-log --redo-only ${DIR}/hotcopy

# create incrementals base dir
mkdir ${DIR}/incrementals

# symlink to /var/log
ln -snf "$LOG_BASE" logs

# create realised directory
cp -ar ${DIR}/hotcopy ${DIR}/realised

# make our cron

cat > "$CRON" <<EOF
# mysql backup - intranet
# incremental
00 * * * *	***REMOVED***	$BACKUP_SCRIPT incremental &>> $LOG_INCREMENTAL
# full
15 23 * * *	***REMOVED***	$BACKUP_SCRIPT full &>> $LOG_FULL
EOF

