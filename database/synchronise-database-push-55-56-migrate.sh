#!/bin/bash
#set -x
# Rsync the database files from a db backup server (live-slave) to a destination server (env-db)
# This version of the job pushes from the source (instead of pulling from destination)
# Job average time is ~50 minutes on a 65GB DB, will be shorter once file repo is removed (-20GB~)
# COW / Snapshot free space will vary according to how many write operations there are in the time it takes this script to finish,
# so if there are more users and more write operations, keep an eye on snapshot capacity, 1GB is all thats needed atm but 5GB set
# as a precautionary number, job could possibly be run during office hours where there could be much more write operations.


# SETTINGS #
# RUNDECK #
DIR=$(cd "$(dirname "$0")" && pwd)
REMOTE_DB_SERVER="@option.remote_db_server@" # in future generalise in rundeck
SSH_USER="@option.ssh_user@" # try different strategies to avoid creating keys
EXCLUDE_FILE="$DIR/excludeFiles.txt"
JOB_COUNT_DIR="$DIR/counter"
SNAPSHOT_FREESPACE="@option.snapshot_freespace@" # at least 1-2GB to be safe
MAX_RSYNC_THREADS="@option.rsync_threads@" # stay below 9
EXCLUDE_LIST="services service_configuration scheduled_task" # turn into RD multi-valued list from high
MYSQL_CNF_SNAPSHOT="/etc/mysql/my.cnf.snapshot"
MYSQL_SOCKET_SNAPSHOT="/var/run/mysqld/mysqld-snapshot.sock"
MYSQL_LOG_SNAPSHOT="/var/log/mysql/snapshot-error.log"
MYSQL_PORT_SNAPSHOT="3307"

#### Validation ####
# Ensure we're on a db server with snapshot info saved
[ -e "$MYSQL_CNF_SNAPSHOT" ] || die "ERROR: snapshot settings for mysql does not exist!"



# DEBUG #
#DIR="/tmp"
#REMOTE_DB_SERVER="***REMOVED***.22"
#SSH_USER="***REMOVED***"
#EXCLUDE_FILE="$DIR/excludeFiles.txt"
#JOB_COUNT_DIR="$DIR/counter"
#SNAPSHOT_FREESPACE="5000"
#MAX_RSYNC_THREADS="8"
#EXCLUDE_LIST="services service_configuration scheduled_task"

# FUNTIONS
die() { echo $* 1>&2 ; exit 1 ; }

# Check job isn't already running
[ -e "$EXCLUDE_FILE" ] && die "Job is already running, quitting...";

# Prepare our remote commands function
rc () {
  ssh ${SSH_USER}@${REMOTE_DB_SERVER} $@ || { die "ERROR: Failed executing - $@ - on ${REMOTE_DB_SERVER}"; }
}

# rc without dying
rcc () {
  ssh ${SSH_USER}@${REMOTE_DB_SERVER} $@
}

# Backup or Restore qa / test specific tables - do as seperate RD job reference
# call snippets/database/table backup or restore RD job
env_tables () {
  for TABLE in $EXCLUDE_LIST; do
    if [ "$1" == "backup" ]; then
      # see if file exists first
      if rcc test -f "$DIR/***REMOVED***.$TABLE.sql"; then
        echo "INFO: $TABLE backup already exists, skipping..."
      else
        echo "INFO: Backing up ***REMOVED***.$TABLE...$(date)"
        rcc "mysqldump -B ***REMOVED*** --tables "$TABLE" --create-options > "$DIR/***REMOVED***.$TABLE.sql""  || die "ERROR: backup of env tables failed"
      fi
    elif [ "$1" == "restore" ]; then
      echo "INFO: Restoring ***REMOVED***.$TABLE...$(date)"
      rcc "mysql -B ***REMOVED*** < "$DIR/***REMOVED***.$TABLE.sql"" || die "ERROR: restore of env tables failed"
      # cleanup / delete sql file after successful restore
      rcc "rm -f $DIR/***REMOVED***.$TABLE.sql"
    fi
  done
}

# VALIDATION and more settings

# Check we can ssh onto remote mysql server
rc "echo INFO: remote connection successful" || die "ERROR: remote connection failed"

# clear bad connection attempts
#rc mysqladmin flush-hosts

# Check my.cnf location remotely
if rcc test -f /etc/mysql/my.cnf; then
    REMOTE_MYCNF="/etc/mysql/my.cnf"
elif rcc test -f /etc/my.cnf; then
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
# SWAP - local = snapshot, remote is real
REMOTE_MYSQL_DIR=$(rc awk "'/^datadir /{ print \$3 }' "$REMOTE_MYCNF""); [ -z $REMOTE_MYSQL_DIR ] && die "ERROR: remote mysql datadir could not be located"
echo "INFO: remote mysql datadir: $REMOTE_MYSQL_DIR"
REAL_MYSQL_DIR=$(awk '/^datadir/{ print $3 }' "$LOCAL_MYCNF"); [ -z $REAL_MYSQL_DIR ] && die "ERROR: local mysql datadir could not be located"
echo "INFO: local mysql datadir: $REAL_MYSQL_DIR"

# Check for mysql lvm partition ($0~v awk escape path slashes) # swap for local
LVM_MYSQL=$(df -P | awk '$0~v { print $1 }' v=$REAL_MYSQL_DIR); [ -z $LVM_MYSQL ] && die "ERROR: local mysql lvm partition could not be located"

# find srv partition and make sure at least ~5GB free space available # swap for local
LVM_SNAPSHOT=$(df -P | awk '/\/srv|lv_snapshots/ { print $1 }'); [ -z $LVM_SNAPSHOT ] && die "ERROR: /srv or ..lv_snapshots lvm partition could not be located"
if [[ $(df -Pm | awk '/\/srv|lv_snapshots/ { print $4 }') -lt $SNAPSHOT_FREESPACE ]]; then # swap for local
  die "ERROR: Not enough free space for snapshot copy on write operations"
fi

# make directory to contain our list of files to sync, used as a counter and to keep track of what's left to sync (parrallel, non-serial)
[ -d "${JOB_COUNT_DIR}" ] || mkdir "${JOB_COUNT_DIR}"

# What to exclude from rsync operation
#- /***REMOVED***/scheduled_task*
#- /***REMOVED***/service_configuration*
#- /***REMOVED***/services*
cat > ${EXCLUDE_FILE} <<EOF
/mysqld-relay*
/relay-log.info
/mysql-bin.*
/master.info
EOF

# Ensure no snapshot exists # swap for local
echo "Confirming there are no existing snapshots...."
hcp -l | grep "No Hot Copy sessions" || { die "ERROR: Snapshot already exist, exiting..."; }

# Save existing variables
INNODB_DIRTY_PAGES_VALUE=$(mysql -e "show global variables like 'innodb_max_dirty_pages_pct';" | awk '/innodb_max_dirty_pages_pct/ { print $2 }')
INNODB_FAST_SHUTDOWN_VALUE=$(mysql -e "show global variables like 'innodb_fast_shutdown';" | awk '/innodb_fast_shutdown/ { print $2 }')

# Flush data to disk before transfer, create snapshot and resume # swap for local (and no need to specifiy host nor ssh)
echo "INFO: Connecting to source database..."
mysql << EOF > /***REMOVED***/master-info.txt
STOP SLAVE;
FLUSH TABLES WITH READ LOCK;
SYSTEM hcp $LVM_MYSQL -c $LVM_SNAPSHOT 2>&1 > /dev/null
SHOW MASTER STATUS;
UNLOCK TABLES;
START SLAVE;
quit
EOF

[ $? == 0 ] || { die "ERROR: Failed to stop slave, flush, create snapshot, unlock and start slave, log onto DB and check!!!!"; }

# swap for local - should probably rename, e.g. mysqldatadir_snapshot
SNAPSHOT_MYSQL_DIR=$(hcp -l | awk '/Mounted:/ { print $2 }') || { die "ERROR: Failed to locate snapshot mount point!"; }
echo "INFO: Snapshot volume: $SNAPSHOT_MYSQL_DIR"

chown mysql:mysql "$SNAPSHOT_MYSQL_DIR" -R

#### new mysql instance start #####
mysqld_safe --defaults-file="${MYSQL_CNF_SNAPSHOT}" &
sleep 10

mysqladmin --socket="${MYSQL_SOCKET_SNAPSHOT}" --port="$MYSQL_PORT_SNAPSHOT" ping || die "ERROR: Failed to start another mysql instance"
mysql --socket="${MYSQL_SOCKET_SNAPSHOT}" --port="$MYSQL_PORT_SNAPSHOT" << EOF >> "$MYSQL_LOG_SNAPSHOT"
stop slave;
reset slave all;
show warnings;
EOF

mysqladmin --socket="${MYSQL_SOCKET_SNAPSHOT}" --port="$MYSQL_PORT_SNAPSHOT" shutdown || die "ERROR: Failed to shutdown snapshot mysql instance"

echo "INFO: mysql snapshot instance log:"
cat "$MYSQL_LOG_SNAPSHOT"
echo "INFO: end of mysql snapshot log."
##### new mysql instance end #######

# Generate Clean list of files to sync # swaparound
echo "Generating clean list and db file counter...."
cleanList=$(rsync -rtlIP --inplace -n --exclude-from="${EXCLUDE_FILE}" "${SNAPSHOT_MYSQL_DIR}/" "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" | head -n -3 | sed -n '3,$p') || { die "ERROR: Failed to generate list of files to rsync"; }

# Get Total number of files to sync # swaparound
dbCounter=$(rsync -rtlIP --inplace -n --exclude-from="${EXCLUDE_FILE}" "${SNAPSHOT_MYSQL_DIR}/" "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" | head -n -3 | sed -n '3,$p' | wc -l) || { die "ERROR: Failed to count number of files to sync"; }

# Get list of files / tables removed # swaparound
droppedTables=$(rsync -rvn --delete "${SNAPSHOT_MYSQL_DIR}/" "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/" | awk '/^deleting / { print $2 }')

# Backup QA Tables
#env_tables backup
#sleep 5

# Stop mysql remotely
rc service mysql stop
echo "INFO: Ready to rsync..."


# Make directories first (parrallel jobs, can't guarantee sequential order)
for db_file in ${cleanList}; do
  if [[ "${db_file: -1}" == "/" ]]; then
    #if [ ! -d "${REMOTE_MYSQL_DIR}/${db_file}" ]; then # change to test
    if rcc test ! -d "${REMOTE_MYSQL_DIR}/${db_file}"; then
      echo "MAKING NEW FOLDER (remotely): ${REMOTE_MYSQL_DIR}/${db_file}" # change dir to remote mysql dir
      rcc mkdir "${REMOTE_MYSQL_DIR}/${db_file}" # change dir to remote mysql dir
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

    ########################
    # SWAP AROUND !!!!!!!!!
    ########################
    (
    /usr/bin/time -f'%E' rsync -rtlzI --inplace --exclude-from="${EXCLUDE_FILE}" "${SNAPSHOT_MYSQL_DIR}/${db_file}" "${SSH_USER}"@"${REMOTE_DB_SERVER}":"${REMOTE_MYSQL_DIR}/${db_file}" && echo "${db_file} complete"
    rm -rf "${db}"
    ) &
    ##########################
    ##########################
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
## SWAP AROUND ##
hcp -l | grep "Changed Blocks"

# Remove snapshot (/dev/hcp1 hardcoded yes, but we ensured earlier no other snapshots existed)
echo "INFO: Removing snapshot..."
## SWAP AROUND ##
hcp -r /dev/hcp1 > /dev/null || echo "WARNING: Failed to remove remote snapshot!!!!! - REMOVE MANUALLY!!!"
# Assuming it's the only snapshot created!, in future amend if using multiple snapshots.

# MAYBE DO ALL OF BELOW IN SEPERATE JOB DIRECTLY ON REMOTE DB SERVER

# Ensure permissions consistent
rc chown mysql:mysql /var/lib/mysql/ -R  # do remotely
# chown mysql:mysql -R $REMOTE_MYSQL_DIR/

# Clear qa tables - do remotely
#for TABLE in $EXCLUDE_LIST; do
#  rc rm -rf "${REMOTE_MYSQL_DIR}/***REMOVED***/${TABLE}.ibd" ## SWAP AROUND ##
#done
# Will cause startup errors for our excluded tables, restoring backed up env_tables will fix

# Clear tables that have been dropped / removed - do remotely
if [ ! -z "$droppedTables" ]; then
  for i in $droppedTables; do
    echo "INFO: deleting $i"
    rc rm -rf "${REMOTE_MYSQL_DIR}/$i" ## DO REMOTELY ##
  done
else
  echo "INFO: no tables to drop!"
fi

#echo "INFO: Starting mysql..." # do remotely, seperate RD job
#rc service mysql start ## DO REMOTELY ##
#sleep 5 ## DO REMOTELY ##

# Restore our qa tables, if doesn't work will have to go down the discard route
#env_tables restore # do remotely, seperate RD job reference ## DO REMOTELY ##

# Restart again to catch remaining errors
#rc service mysql restart # do remotely, seperate RD job ## DO REMOTELY ##

rcc mysqladmin flush-hosts

#rcc mysql -e 'stop slave; reset slave all;' || echo "WARNING: !!!! slave info could not be removed !!!!!!"

echo "INFO: Cleanup operations..."
rm -rf "${EXCLUDE_FILE}"
rm -rf "${JOB_COUNT_DIR}"

echo "INFO: master log positions"
cat /***REMOVED***/master-info.txt