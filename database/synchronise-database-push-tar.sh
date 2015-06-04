#!/bin/bash
#set -x
# Rsync the database files from a db backup server (live-slave) to a destination server (env-db)
# This version of the job pushes from the source (instead of pulling from destination)
# Job average time is ~50 minutes on a 65GB DB, will be shorter once file repo is removed (-20GB~)
# COW / Snapshot free space will vary according to how many write operations there are in the time it takes this script to finish,
# so if there are more users and more write operations, keep an eye on snapshot capacity, 1GB is all thats needed atm but 5GB set
# as a precautionary number, job could possibly be run during office hours where there could be much more write operations.


# sync with tar over ssh instead, significantly quicker (4x)
# poc -> tar -cf - -C /var/lib/mysql . [--exclude a* --exclude-from=${EXCLUDE_FILE}] | ssh rundeck@<destination> \
# -T -c arcfour -o Compression=no -x \
# "sudo tar -xf - -C /var/lib/mysql"
# set the lowest encryption and no compression to ensure speedy transfers, on par with netcat but secure.
# this script is specifically to be run on backup2 (new backup server)

# SETTINGS #
# RUNDECK #
DIR=$(cd "$(dirname "$0")" && pwd)
REMOTE_DB_SERVER="@option.remote_db_server@" # in future generalise in rundeck
SSH_USER="rundeck" # using ssh-agent feature in RD 2.4.0+
SSH_OPTIONS="-T -c arcfour -o StrictHostKeyChecking=no -o Compression=no -x"
EXCLUDE_FILE="$DIR/excludeFiles.txt" # converted for tar --exclude-from feature
SNAPSHOT_FREESPACE="@option.snapshot_freespace@" # at least 1-2GB to be safe
EXCLUDE_LIST="services service_configuration scheduled_task mailqueue" # turn into RD multi-valued list from high
USE_BACKUP="@option.use_backup@" # don't use to repair slave, always errors, but fine for non-slaves

# FUNTIONS
die() { echo $* 1>&2 ; exit 1 ; }

cleanup ()
{
        echo "INFO: Cleanup operations..."
        # clean up files
        rm -rf "${EXCLUDE_FILE}"

        # Remove snapshot (/dev/hcp1 hardcoded yes, but we ensured earlier no other snapshots existed)
        if [ -e /dev/hcp1 ]; then
            echo "INFO: Removing snapshot..."
            hcp -r /dev/hcp1 > /dev/null || echo "WARNING: Failed to remove remote snapshot!!!!! - REMOVE MANUALLY!!!"
        fi
}

trap cleanup EXIT

# Check job isn't already running
[ -e "$EXCLUDE_FILE" ] && die "Job is already running, quitting...";

# Prepare our remote commands function
rc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_DB_SERVER} "sudo sh -c '$@'" < /dev/null || { die "ERROR: Failed executing - $@ - on ${REMOTE_DB_SERVER}"; }
}

# rc without dying
rcc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_DB_SERVER} "sudo sh -c '$@'" < /dev/null
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
        rcc "mysqldump -B ***REMOVED*** --tables $TABLE --create-options > $DIR/***REMOVED***.$TABLE.sql"  || die "ERROR: backup of env tables failed"
      fi
    elif [ "$1" == "restore" ]; then
      echo "INFO: Restoring ***REMOVED***.$TABLE...$(date)"
      rcc "mysql -B ***REMOVED*** < $DIR/***REMOVED***.$TABLE.sql" || die "ERROR: restore of env tables failed"
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


# Backup QA Tables
env_tables backup
sleep 5

# What files to exclude from sync
cat > ${EXCLUDE_FILE} <<EOF
*mysqld-relay*
*relay-log.info
*mysql-bin.*
*master.info
EOF

# Check data directory location (locally, remote will actually be the snapshot location)
#REMOTE_MYSQL_DIR=$(rc awk "'/^datadir /{ print \$3 }' $REMOTE_MYCNF"); [ -z "$REMOTE_MYSQL_DIR" ] && die "ERROR: remote mysql datadir could not be located"
REMOTE_MYSQL_DIR=$(rc grep ^datadir $REMOTE_MYCNF | grep -oE "/.*"); [ -z "$REMOTE_MYSQL_DIR" ] && die "ERROR: remote mysql datadir could not be located"
echo "INFO: remote mysql datadir: $REMOTE_MYSQL_DIR"
REAL_MYSQL_DIR=$(awk '/^datadir/{ print $3 }' "$LOCAL_MYCNF"); [ -z "$REAL_MYSQL_DIR" ] && die "ERROR: local mysql datadir could not be located"
echo "INFO: local mysql datadir: $REAL_MYSQL_DIR"

# Check for mysql lvm partition ($0~v awk escape path slashes) # swap for local
LVM_MYSQL=$(df -P | awk '$0~v { print $1 }' v=$REAL_MYSQL_DIR); [ -z "$LVM_MYSQL" ] && die "ERROR: local mysql lvm partition could not be located"

# Check there is enough storage space on the destination for the data amount on source
REAL_MYSQL_DIR_USED_SPACE=$(df -P $REAL_MYSQL_DIR | tail -n1 | awk '{print $3}')
REMOTE_MYSQL_DIR_CAPACITY=$(rc "df -P $REMOTE_MYSQL_DIR" | tail -n1 | awk '{print $2}')
#Assumes a dedicated partition for mysql data, we check capacity vs free space as we'll delete the whole directory

[ $REAL_MYSQL_DIR_USED_SPACE -lt $REMOTE_MYSQL_DIR_CAPACITY ] || rc "ERROR: There is not enough space on the destination - source : $(($REAL_MYSQL_DIR_USED_SPACE / 1024 / 1024))GB, destination : $(($REMOTE_MYSQL_DIR_CAPACITY / 1024 / 1024))"


if [[ "$USE_BACKUP" == "yes" ]]; then
  # find latest backup and send
  HOT_COPY="/srv/r5/backups/mysql-innobackupex/hotcopy"
  [ -d "${HOT_COPY}" ] || die "ERROR: Can not locate latest backup at ${HOT_COPY}."

  # job should not be run during or close time of full backup / roll in (11pm)
  # let's say no later than 9pm
  [[ "$(date +%H)" -ge 21 ]] && die "ERROR: To avoid inconsistent data, refusing to sync as the full backup and incremental will take place soon (11pm)"

  FINAL_MYSQL_DIR="$HOT_COPY"
else
  # continue with snapshot process
  # find srv partition and make sure at least ~5GB free space available # swap for local
  LVM_SNAPSHOT=$(df -P | awk '/\/srv|lv_snapshots/ { print $1 }' | head -n 1); [ -z "$LVM_SNAPSHOT" ] && die "ERROR: /srv or ..lv_snapshots lvm partition could not be located"
  if [[ $(df -Pm | awk '/\/srv|lv_snapshots/ { print $4 }' | head -n 1) -lt "$SNAPSHOT_FREESPACE" ]]; then # swap for local
    die "ERROR: Not enough free space for snapshot copy on write operations"
  fi

  # Ensure no snapshot exists # swap for local
  echo "Confirming there are no existing snapshots...."
  hcp -v
  hcp -l | grep "No Hot Copy sessions" || { die "ERROR: Snapshot already exist, exiting..."; }

  # Flush data to disk before transfer, create snapshot and resume # swap for local (and no need to specifiy host nor ssh)
  echo "INFO: Connecting to source database..."

  # so mysql can find .my.cnf for ***REMOVED*** user using environment variable (when using sudo -E)
  HOME=/***REMOVED***

mysql << EOF
STOP SLAVE;
FLUSH TABLES WITH READ LOCK;
SYSTEM hcp -o $LVM_MYSQL -c $LVM_SNAPSHOT 2>&1 > /dev/null
UNLOCK TABLES;
START SLAVE;
quit
EOF

  [ $? == 0 ] || { die "ERROR: Failed to stop slave, flush, create snapshot, unlock and start slave, log onto DB and check!!!!"; }

  # swap for local - should probably rename, e.g. mysqldatadir_snapshot
  SNAPSHOT_MYSQL_DIR=$(hcp -l | awk '/Mounted:/ { print $2 }') || { die "ERROR: Failed to locate snapshot mount point!"; }
  echo "INFO: Snapshot volume: $SNAPSHOT_MYSQL_DIR"

  FINAL_MYSQL_DIR="$SNAPSHOT_MYSQL_DIR"
fi


# Stop mysql remotely
rcc service mysql stop

# clear remote mysql datadir
echo "INFO: Clearing destination $REMOTE_MYSQL_DIR ..."
rc "rm -rf ${REMOTE_MYSQL_DIR}/*"
echo "INFO: Ready to sync..."

############# MAIN TASK ####################################################################
START_TIME=$(date)
echo "####################################################################"
echo "INFO: Starting sync..."
tar -cvf - -C "${FINAL_MYSQL_DIR}" --exclude-from="${EXCLUDE_FILE}" . \
| ssh ${SSH_OPTIONS} "${SSH_USER}"@"${REMOTE_DB_SERVER}" "sudo tar -xf - -C ${REMOTE_MYSQL_DIR}"

[ $? == 0 ] || { die "ERROR: the sync job failed!"; }

echo "INFO: Finish sync:"
echo "INFO: Started - $START_TIME"
echo "INFO: Ended   - $(date)"
echo "####################################################################"
############# END MAIN TASK ####################################################################

# Note how big snapshot / COW parition got
echo "INFO: Snapshot / COW final size..."
## SWAP AROUND ##
hcp -l | grep "Changed Blocks"

# Ensure permissions consistent
rc chown mysql:mysql "${REMOTE_MYSQL_DIR}/" -R

echo "INFO: Starting mysql..." # do remotely, seperate RD job
rc service mysql start ## DO REMOTELY ##
sleep 5 ## DO REMOTELY ##

# Restore our qa tables, if doesn't work will have to go down the discard route
env_tables restore # do remotely, seperate RD job reference ## DO REMOTELY ##

# Restart again to catch remaining errors
rc service mysql restart # do remotely, seperate RD job ## DO REMOTELY ##

rcc 'mysqladmin flush-hosts'

# working
# rcc 'mysql -e "stop slave;"' # put single quotes around entire command

rcc 'mysql -e "stop slave;"' || echo "WARNING: !!!! could not stop slave replication !!!!!!"
rcc 'mysql -e "reset slave all;"' || echo "WARNING: !!!! slave info could not be removed !!!!!!"


