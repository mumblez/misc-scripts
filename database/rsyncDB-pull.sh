#!/bin/bash
# Rsync the database files from backup server (live-slave) to test server (db3)
# Job average time is ~50 minutes on a 65GB DB, will be shorter once file repo is removed (-20GB~)
# COW / Snapshot free space will vary according to how many write operations there are in the time it takes this script to finish,
# so if there are more users and more write operations, keep an eye on snapshot capacity, 1GB is all thats needed atm but 5GB set
# as a precautionary number, job could possibly be run during office hours where there could be much more write operations.


# SETTINGS #
DIR=$(cd "$(dirname "$0")" && pwd)
REMOTE_DB_SERVER="***REMOVED***.230" # in future generalise in rundeck
SSH_USER="***REMOVED***"
EXCLUDE_FILE="$DIR/excludeFiles.txt"
JOB_COUNT_DIR="$DIR/counter"
SNAPSHOT_FREESPACE=5000 # make configurable in rundeck, will need to be adjusted in future according to how write busy the DB gets
MAX_RSYNC_THREADS=10 # make configurable in rundeck
EXCLUDE_LIST="services service_configuration scheduled_task"
START_TIME=$(date)


# FUNTIONS
die() { echo $* 1>&2 ; exit 1 ; }

# Prepare our remote commands function
rc () {
  ssh ${SSH_USER}@${REMOTE_DB_SERVER} $@ || { die "Failed executing - $@ - on ${REMOTE_DB_SERVER}"; }
}

# Backup or Restore qa / test specific tables
env_tables () {
  for TABLE in $EXCLUDE_LIST; do
    if [[ "$1" == "backup" && ! -f "$DIR/***REMOVED***.$TABLE.sql" ]]; then
      echo "Backing up ***REMOVED***.$TABLE...$(date)"
      mysqldump -B ***REMOVED*** --tables "$TABLE" --create-option > "$DIR/***REMOVED***.$TABLE.sql"
    elif [ "$1" == "restore" ]; then
      echo "Restoring ***REMOVED***.$TABLE...$(date)"
      mysql -B ***REMOVED*** < "$DIR/***REMOVED***.$TABLE.sql"
      # cleanup / delete sql file after successful restore
      rm -f "$DIR/***REMOVED***.$TABLE"
    fi
  done
}


# VALIDATION and more settings

# Check job isn't already running
[ -e "$EXCLUDE_FILE" ] && { die "Job is already running, quitting..."; }

# Check we can ssh onto remote mysql server
rc "echo ssh login test"

# Check my.cnf location remotely
if rc test -f /etc/mysql/my.cnf; then
    REMOTE_MYCNF="/etc/mysql/my.cnf"
elif rc test -f /etc/my.cnf; then
    REMOTE_MYCNF="/etc/my.cnf"
else
    die "ERROR: remote my.cnf could not be found!"
fi

# Check my.cnf location locally
if test -f /etc/mysql/my.cnf; then
    LOCAL_MYCNF="/etc/mysql/my.cnf" # debian
elif test -f /etc/my.cnf; then # redhat / centos
    LOCAL_MYCNF="/etc/my.cnf"
else
    die "ERROR: local my.cnf could not be found!"
fi

# Check data directory location (locally, remote will actually be the snapshot location)
LOCAL_MYSQL_DIR=$(awk '/^datadir/{ print $3 }' "$LOCAL_MYCNF"); [ -z $LOCAL_MYSQL_DIR ] && die "ERROR: Local mysql datadir could not be located"
echo "INFO: local mysql datadir: $LOCAL_MYSQL_DIR"
REAL_REMOTE_MYSQL_DIR=$(rc awk "'/^datadir/{ print \$3 }' "$REMOTE_MYCNF""); [ -z $REAL_REMOTE_MYSQL_DIR ] && die "ERROR: Remote mysql datadir could not be located"
echo "INFO: remote mysql datadir: $REAL_REMOTE_MYSQL_DIR"

# Check for mysql lvm partition ($0~v awk escape path slashes)
LVM_MYSQL=$(rc "df -P" | awk '$0~v { print $1 }' v=$REAL_REMOTE_MYSQL_DIR); [ -z $LVM_MYSQL ] && die "ERROR: Remote mysql lvm partition could not be located"

# find srv partition and make sure at least ~5GB free space available
LVM_SNAPSHOT=$(rc "df -P" | awk '/\/srv|lv_snapshots/ { print $1 }'); [ -z $LVM_SNAPSHOT ] && die "ERROR: /srv lvm partition could not be located"
if [[ $(rc "df -Pm" | awk '/\/srv/ { print $4 }') -lt $SNAPSHOT_FREESPACE ]]; then
  die "ERROR: Not enough free space for snapshot copy on write operations"
fi

# make directory to contain our list of files to sync, used as a counter and to keep track of what's left to sync (parrallel, non-serial)
[ -d "${JOB_COUNT_DIR}" ] || mkdir "${JOB_COUNT_DIR}"

# What to exclude from rsync operation
cat > ${EXCLUDE_FILE} <<EOF
- /***REMOVED***/scheduled_task*
- /***REMOVED***/service_configuration*
- /***REMOVED***/services*
- /mysqld-relay*
- /relay-log.info 
- /mysql-bin.*
- /master.info 
EOF

# Ensure no snapshot exists
echo "Confirming there are no existing snapshots...."
rc "hcp -l" | grep "No Hot Copy sessions" || { die "Snapshot already exist, exiting..."; }

# Flush data to disk before transfer, create snapshot and resume
echo "INFO: Connecting to source database..."
mysql --defaults-file=/***REMOVED***/.my.cnf.backup -h "$REMOTE_DB_SERVER" << EOF
STOP SLAVE;
FLUSH TABLES WITH READ LOCK;
SYSTEM ssh "$SSH_USER"@"$REMOTE_DB_SERVER" "hcp -o $LVM_MYSQL -c $LVM_SNAPSHOT" 2>&1 > /dev/null
UNLOCK TABLES;
START SLAVE;
quit
EOF

[ $? == 0 ] || { die "Failed to connect to remote DB, stop slave, flush, create snapshot, unlock and start slave, logon to source DB and check!!!!"; }

REMOTE_MYSQL_DIR=$(rc "hcp -l" | awk '/Mounted:/ { print $2 }') || { die "ERROR: Failed to locate snapshot mount point!"; }
echo "INFO: Remote snapshot volume: $REMOTE_MYSQL_DIR"

# Generate Clean list of files to sync
echo "Generating clean list and db file counter...."
cleanList=$(rsync -rtlIP --inplace -n --exclude-from="${EXCLUDE_FILE}" "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" "${LOCAL_MYSQL_DIR}/" | head -n -3 | sed -n '3,$p') || { die "Failed to generate list of files to rsync from remote server"; }

# Get Total number of files to sync
dbCounter=$(rsync -rtlIP --inplace -n --exclude-from="${EXCLUDE_FILE}" "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" "${LOCAL_MYSQL_DIR}/" | head -n -3 | sed -n '3,$p' | wc -l) || { die "Failed to count number of files to sync"; }

# Get list of files / tables removed
droppedTables=$(rsync -rvn --delete "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" "${LOCAL_MYSQL_DIR}/" | awk '/^deleting / { print $2 }')

# Backup QA Tables
env_tables backup

# Stop mysql locally
service mysql stop
echo "INFO: Ready to rsync..."


# Make directories first (parrallel jobs, can't guarantee sequential order)
for db_file in ${cleanList}; do
  if [[ "${db_file: -1}" == "/" ]]; then
    if [ ! -d "${LOCAL_MYSQL_DIR}/${db_file}" ]; then
      echo "MAKING NEW FOLDER: ${LOCAL_MYSQL_DIR}/${db_file}"
      mkdir "${LOCAL_MYSQL_DIR}/${db_file}"
    fi
  fi
done

# Main loop
for db_file in ${cleanList}; do
  while [ $(ls $JOB_COUNT_DIR | wc -l ) -eq $MAX_RSYNC_THREADS ];
  do
    # As we background the rsync jobs, we can safely wait, and check every 2 seconds
    # until there are free slots (we check externally via files)
    sleep 2
    echo "$dbCounter transfers remain"
  done
  if [[ "${db_file: -1}" != "/" ]]; then
    db=$(mktemp ${JOB_COUNT_DIR}/$(basename ${db_file})-file.XXXX)
    #db=$(basename "$db_file") # tables may not be unique across databases
    # Using same cleanList so need to check again for folder
    touch "${db}"
    (
    /usr/bin/time -f'%E' rsync -rtlzI --inplace --exclude-from="${EXCLUDE_FILE}" "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/${db_file}" "${LOCAL_MYSQL_DIR}/${db_file}" && echo "${db_file} complete"
    rm -rf "${db}"
    ) &
  fi
  let "dbCounter-=1"
  if [ $dbCounter -lt 10 ]; then
    echo "$dbCounter transfers remain"
    echo "In progress...."
    echo "$(ls -1 $JOB_COUNT_DIR | rev | cut -c 11- | rev)"
  fi
done

# Wait until all background rsync jobs complete
wait
echo "INFO: rsync complete!"

# Note how big snapshot / COW parition got
echo "INFO: Snapshot / COW final size..."
rc "hcp -l" | grep "Changed Blocks"

# Remove snapshot (/dev/hcp1 hardcoded yes, but we ensured earlier no other snapshots existed)
echo "INFO: Removing remote snapshot..."
rc hcp -r /dev/hcp1 > /dev/null || echo "WARNING: Failed to remove remote snapshot!!!!! - REMOVE MANUALLY!!!"
# Assuming it's the only snapshot created!, in future amend if using multiple snapshots.

# Ensure permissions consistent
chown mysql:mysql /var/lib/mysql/ -R

# Clear qa tables
for TABLE in $EXCLUDE_LIST; do
  rm -rf "${LOCAL_MYSQL_DIR}/***REMOVED***/${TABLE}.ibd"
done
# Will cause startup errors for our excluded tables, restoring backed up env_tables will fix

# Clear tables that have been dropped / removed
if [ ! -z "$droppedTables" ]; then
  for i in $droppedTables; do
    echo "INFO: deleting $i"
    rm -rf "${LOCAL_MYSQL_DIR}/$i"
  done
else
  echo "INFO: no tables to drop!"
fi

echo "INFO: Starting mysql..."
service mysql start
sleep 5

# Restore our qa tables, if doesn't work will have to go down the discard route
env_tables restore

# Restart again to catch remaining errors
service mysql restart

# Cleanup
echo "INFO: Cleanup operations..."
rm -rf "${EXCLUDE_FILE}"
rm -rf "${JOB_COUNT_DIR}"
echo "==========================="
echo "INFO: Start time: $START_TIME"
echo "INFO: End time: $(date)"
echo "======= COMPLETE =========="
