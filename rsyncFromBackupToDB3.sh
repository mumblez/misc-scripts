#!/bin/bash
# Rsync the database files from backup server (live-slave) to test server (db3)
DIR=$(cd "$(dirname "$0")" && pwd)
BACKUP_DB_SERVER="***REMOVED***.230"
LVM_MYSQL="/dev/mapper/335302-mysql"
LVM_SNAPSHOT="/dev/mapper/335302-srv"
SSH_USER="***REMOVED***"
EXCLUDE_FILE="$DIR/excludeFiles.txt"
JOB_COUNT_DIR="$DIR/counter"
MYSQL_DATA_DIR_SOURCE="/var/lib/mysql"
MAX_THREAD=10
EXCLUDE_LIST="services service_configuration scheduled_task"
EXCLUDE_TABLES="emaillog commlog eventlog"

# Check job isn't already running
[ -e "$EXCLUDE_FILE" ] && { die "Job is already running, quitting..."; }

# Backup or Restore qa / test specific tables
qatables () {
   for TABLE in $EXCLUDE_LIST; do
      if [ "$1" == "backup" ]; then
          echo "Backing up ***REMOVED***.$TABLE...$(date)"
          mysqldump -B ***REMOVED*** --tables "$TABLE" --create-option > /tmp/***REMOVED***."$TABLE".sql
      elif [ "$1" == "restore" ]; then
          echo "Restoring ***REMOVED***.$TABLE...$(date)"
          mysql -B ***REMOVED*** < /tmp/***REMOVED***."$TABLE".sql
      fi
    done
}

# Remove redundant logs from ***REMOVED*** db
remove_cl_logs () {
    for TABLE in $EXCLUDE_TABLES; do
        mysql ***REMOVED*** -e "drop table $TABLE;" && echo "$TABLE" dropped! || echo "ERROR: Failed to drop $TABLE"
    done
}

# TO DO:
# exclude commlog, emaillog and eventlog and drop tables after mysql start (need to test)

[ -d "${JOB_COUNT_DIR}" ] || mkdir "${JOB_COUNT_DIR}"

#cat > ${EXCLUDE_FILE} <<EOF
#- /cognohr/
#- /***REMOVED***/commlog*
#- /***REMOVED***/emaillog*
#- /***REMOVED***/eventlog*
#- /***REMOVED***/scheduled_task*
#- /***REMOVED***/service_configuration*
#- /***REMOVED***/services*
#- /debian*
#- /lost*found/
#- /master.info 
#- /mysql*
#- /percona/
#- /performance_schema/
#- /phpmyadmin/
#- /relay-log.info 
#- /test/
#EOF

cat > ${EXCLUDE_FILE} <<EOF
- /***REMOVED***/scheduled_task*
- /***REMOVED***/service_configuration*
- /***REMOVED***/services*
- /***REMOVED***/commlog*
- /***REMOVED***/emaillog*
- /***REMOVED***/eventlog*
- /mysqld-relay*
- /relay-log.info 
- /mysql-bin.*
- /master.info 
EOF

die() { echo $* 1>&2 ; exit 1 ; }
#verbose() { echo "VERBOSE : $*" 1>&2 ; }
START_TIME=$(date)

# Prepare our remote commands function
rc () {
    ssh ${SSH_USER}@${BACKUP_DB_SERVER} $1 || { die "Failed executing - $1 - on ${BACKUP_DB_SERVER}"; }
}

# Ensure no snapshot exists
echo "Confirming there are no existing snapshots...."
rc "hcp -l" | grep "No Hot Copy sessions" || { die "Snapshot already exist, exiting..."; }

# Flush data to disk before transfer, create snapshots and resume
echo "Connecting to source database..."
mysql --defaults-file=/***REMOVED***/.my.cnf.backup -h "$BACKUP_DB_SERVER" << EOF
STOP SLAVE;
FLUSH TABLES WITH READ LOCK;
SYSTEM ssh "$SSH_USER"@"$BACKUP_DB_SERVER" "hcp -o $LVM_MYSQL -c $LVM_SNAPSHOT"
UNLOCK TABLES;
START SLAVE;
quit
EOF
[ $? == 0 ] || { die "Failed to connect to remote DB, stop slave, flush, create snapshot, unlock and start slave, logon to source DB and check!!!!"; }

REMOTE_MYSQL_DIR=$(rc "hcp -l" | grep "Mounted:" | awk '{ print $2 }') || { die "Failed to locate snapshot mount point!"; }
echo "==== Remote snapshot volume: $REMOTE_MYSQL_DIR =========="
sleep 10

# Generate Clean list of files to sync
echo "Generating clean list and db file counter...."
cleanList=$(rsync -rtlIP --inplace -n --exclude-from="${EXCLUDE_FILE}" "${SSH_USER}"@"${BACKUP_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" "${MYSQL_DATA_DIR_SOURCE}/" | head -n -3 | sed -n '3,$p') || { die "Failed to generate list of files to rsync from remote server"; }

# Get Total number of files to sync
dbCounter=$(rsync -rtlIP --inplace -n --exclude-from="${EXCLUDE_FILE}" "${SSH_USER}"@"${BACKUP_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" "${MYSQL_DATA_DIR_SOURCE}/" | head -n -3 | sed -n '3,$p' | wc -l) || { die "Failed to count number of files to sync"; }


# Backup QA Tables
qatables backup

# Stop mysql locally
service mysql stop
echo "Ready to rsync..."

# Main loop
for db_file in ${cleanList}; do
    while [ $(ls $JOB_COUNT_DIR | wc -l ) -eq $MAX_THREAD ];
    do
        # As we background the rsync jobs, we can safely wait, and check every 2 seconds
        # until there are free slots (we check externally via files)
        sleep 2
        echo "$dbCounter transfers remain"
    done
    db=$(mktemp ${JOB_COUNT_DIR}/$(basename ${db_file})-file.XXXX)
    #db=$(basename "$db_file") # tables may not be unique across databases
    touch "${db}"
    (
        /usr/bin/time -f'%E' rsync -rtlzI --inplace --exclude-from="${EXCLUDE_FILE}" "${SSH_USER}"@"${BACKUP_DB_SERVER}":"${REMOTE_MYSQL_DIR}/${db_file}" "${MYSQL_DATA_DIR_SOURCE}/${db_file}" && echo "${db_file} complete"
        rm -rf "${db}"
    ) &
    let "dbCounter-=1"
    if [ $dbCounter -lt 10 ]; then
        echo "$dbCounter transfers remain"
        echo "In progress...."
        echo "$(ls -1 $JOB_COUNT_DIR | rev | cut -c 11- | rev)"
    fi
done

# Wait til all background rsync jobs complete
wait
echo "rsync complete!"

# Remove snapshot
echo "Removing remote snapshot..."
rc "hcp -r /dev/hcp1" || echo "ERROR: Failed to remove remote snapshot!!!!! - REMOVE MANUALLY!!!"
# Assuming it's the only snapshot created!, in future amend if using multiple snapshots.

# Ensure permissions consistent
chown mysql:mysql /var/lib/mysql -R

# Clear qa tables
for TABLE in $EXCLUDE_LIST; do
    rm -rf "${MYSQL_DATA_DIR_SOURCE}/***REMOVED***/${TABLE}.ibd"
done
# Will cause startup errors, dropping and restoring qa tables should fix, need to test

echo "Starting mysql..."
service mysql start
sleep 5

# Restore our qa tables, if doesn't work will have to go down the discard route
qatables restore
# Drop log tables
remove_cl_logs

# Cleanup
rm -rf "${EXCLUDE_FILE}"
rm -rf "${JOB_COUNT_DIR}"
echo "==========================="
echo "Start time: $START_TIME"
echo "End time: $(date)"
echo "======= COMPLETE =========="