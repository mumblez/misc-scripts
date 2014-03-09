#!/bin/bash
# Rsync the database files from backup server (live-slave) to test server (db3)


# SETTINGS #
DIR=$(cd "$(dirname "$0")" && pwd)
REMOTE_DB_SERVER="***REMOVED***.230"
#LVM_MYSQL="/dev/mapper/335302-mysql" # generalise
#LVM_SNAPSHOT="/dev/mapper/335302-srv" # generalise
SSH_USER="***REMOVED***"
EXCLUDE_FILE="$DIR/excludeFiles.txt"
JOB_COUNT_DIR="$DIR/counter"
#LOCAL_MYSQL_DIR="/var/lib/mysql" # if default location used, no need to change
SNAPSHOT_FREESPACE=5000 # make configurable in rundeck
MAX_RSYNC_THREADS=10 # make configurable in rundeck
EXCLUDE_LIST="services service_configuration scheduled_task"
START_TIME=$(date)


# FUNTIONS
die() { echo $* 1>&2 ; exit 1 ; }
#verbose() { echo "VERBOSE : $*" 1>&2 ; }

# Prepare our remote commands function
rc () {
  ssh ${SSH_USER}@${REMOTE_DB_SERVER} $@ || { die "Failed executing - $@ - on ${REMOTE_DB_SERVER}"; }
}

# Backup or Restore qa / test specific tables
qatables () {
  for TABLE in $EXCLUDE_LIST; do
    if [[ "$1" == "backup" && ! -f "$DIR/***REMOVED***.$TABLE" ]]; then
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


# VALIDATION

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
elif rc test -f /etc/my.cnf; then # redhat / centos
    LOCAL_MYCNF="/etc/my.cnf"
else
    die "ERROR: local my.cnf could not be found!"
fi

# Check data directory location (locally, remote will actually be the snapshot location)
LOCAL_MYSQL_DIR=$(awk '/^datadir /{ print $3 }' "$LOCAL_MYCNF"); [ -z $LOCAL_MYSQL_DIR ] && die "ERROR: Local mysql datadir could not be located"
REAL_REMOTE_MYSQL_DIR=$(rc awk '/^datadir /{ print $3 }' "$REMOTE_MYCNF"); [ -z $REMOTE_MYSQL_DIR ] && die "ERROR: Remote mysql datadir could not be located"

# Check for mysql lvm partition
LVM_MYSQL=$(rc "df -P" | awk '/'"$REAL_REMOTE_MYSQL_DIR"'/ { print $1 }'); [ -z $LVM_MYSQL ] && die "ERROR: Remote mysql lvm partition could not be located"

# find srv partition and make sure at least ~5GB free space available
LVM_SNAPSHOT=$(rc "df -P" | awk '/\/srv/ { print $1 }'); [ -z $LVM_SNAPSHOT ] && die "ERROR: /srv lvm partition could not be located"
if [[ $(rc "df -Pm" | awk '/\/srv/ { print $4 }') -lt $SNAPSHOT_FREESPACE ]]; then
  die "ERROR: Not enough free space for snapshot copy on write operations"
fi

[ -d "${JOB_COUNT_DIR}" ] || mkdir "${JOB_COUNT_DIR}"


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
echo "Connecting to source database..."
mysql --defaults-file=/***REMOVED***/.my.cnf.backup -h "$REMOTE_DB_SERVER" << EOF
STOP SLAVE;
FLUSH TABLES WITH READ LOCK;
SYSTEM ssh "$SSH_USER"@"$REMOTE_DB_SERVER" "hcp -o $LVM_MYSQL -c $LVM_SNAPSHOT" 2>&1 > /dev/null
UNLOCK TABLES;
START SLAVE;
quit
EOF

[ $? == 0 ] || { die "Failed to connect to remote DB, stop slave, flush, create snapshot, unlock and start slave, logon to source DB and check!!!!"; }

REMOTE_MYSQL_DIR=$(rc "hcp -l" | grep "Mounted:" | awk '{ print $2 }') || { die "Failed to locate snapshot mount point!"; }
echo "==== Remote snapshot volume: $REMOTE_MYSQL_DIR =========="
#sleep 10

# Generate Clean list of files to sync
echo "Generating clean list and db file counter...."
cleanList=$(rsync -rtlIP --inplace -n --exclude-from="${EXCLUDE_FILE}" "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" "${LOCAL_MYSQL_DIR}/" | head -n -3 | sed -n '3,$p') || { die "Failed to generate list of files to rsync from remote server"; }

# Get Total number of files to sync
dbCounter=$(rsync -rtlIP --inplace -n --exclude-from="${EXCLUDE_FILE}" "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" "${LOCAL_MYSQL_DIR}/" | head -n -3 | sed -n '3,$p' | wc -l) || { die "Failed to count number of files to sync"; }

# Get list of files / tables removed
droppedTables=$(rsync -rvn --delete "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" "${LOCAL_MYSQL_DIR}/" | awk '/^deleting / { print $2 }')

# Backup QA Tables
qatables backup

# Stop mysql locally
service mysql stop
echo "Ready to rsync..."


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

# Wait til all background rsync jobs complete
wait
echo "rsync complete!"

# Remove snapshot (/dev/hcp1 hardcoded yes, but we ensured earlier no other snapshots existed)
echo "Removing remote snapshot..."
rc hcp -r /dev/hcp1 > /dev/null || echo "ERROR: Failed to remove remote snapshot!!!!! - REMOVE MANUALLY!!!"
# Assuming it's the only snapshot created!, in future amend if using multiple snapshots.

# Ensure permissions consistent
chown mysql:mysql /var/lib/mysql/ -R

# Clear qa tables
for TABLE in $EXCLUDE_LIST; do
  rm -rf "${LOCAL_MYSQL_DIR}/***REMOVED***/${TABLE}.ibd"
done
# Will cause startup errors, dropping and restoring qa tables should fix

# Clear tables that have been dropped / removed
if [ ! -z $droppedTables ]; then
  for i in $droppedTables; do
    rm -rf "${LOCAL_MYSQL_DIR}/$i"
  done
fi

echo "Starting mysql..."
service mysql start
sleep 5

# Restore our qa tables, if doesn't work will have to go down the discard route
qatables restore

# Cleanup
rm -rf "${EXCLUDE_FILE}"
rm -rf "${JOB_COUNT_DIR}"
echo "==========================="
echo "Start time: $START_TIME"
echo "End time: $(date)"
echo "======= COMPLETE =========="