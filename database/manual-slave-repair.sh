#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
REMOTE_DB_SERVER="***REMOVED***.129" # in future generalise in rundeck
SSH_USER="***REMOVED***" # using ssh-agent feature in RD 2.4.0+
SSH_OPTIONS="-T -c arcfour -o StrictHostKeyChecking=no -o Compression=no -x"
EXCLUDE_FILE="$DIR/excludeFiles.txt" # converted for tar --exclude-from feature
MYSQL_VERSION_MASTER=$(mysqladmin version | grep 'Server version' | grep -oE "5.[56]")

# FUNTIONS
die() { echo $* 1>&2 ; exit 1 ; }

cleanup ()
{
	echo "INFO: Cleanup operations..."
	# clean up files
	rm -rf "${EXCLUDE_FILE}"
	rm -f "$MASTER_LOG"

	# Remove snapshot (/dev/hcp1 hardcoded yes, but we ensured earlier no other snapshots existed)
    if [ -e /dev/hcp1 ]; then
	    echo "INFO: Removing snapshot..."
	    hcp -r /dev/hcp1 > /dev/null || echo "WARNING: Failed to remove remote snapshot!!!!! - REMOVE MANUALLY!!!"
    fi
}

trap cleanup EXIT

if [ $# -eq 1 ]; then
  REMOTE_DB_SERVER="$2"
fi

# Check job isn't already running
[ -e "$EXCLUDE_FILE" ] && die "Job is already running, quitting...";

# Prepare our remote commands function
rc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_DB_SERVER} "sudo $@" || { die "ERROR: Failed executing - $@ - on ${REMOTE_DB_SERVER}"; }
}

# rc without dying
rcc () {
  ssh $SSH_OPTIONS ${SSH_USER}@${REMOTE_DB_SERVER} "sudo $@"
}

MYSQL_VERSION_SLAVE=$(rcc 'mysqladmin version' | grep 'Server version' | grep -oE "5.[56]")
[ -z "$MYSQL_VERSION_SLAVE" ] && MYSQL_VERSION_SLAVE=$(rc dpkg -l | grep 'mysql-server-' | grep -oE "5.[56]" | head -n 1)
echo "INFO: mysql version - master = $MYSQL_VERSION_MASTER"
echo "INFO: mysql version - slave = $MYSQL_VERSION_SLAVE"


# VALIDATION and more settings

# Check we can ssh onto remote mysql server
rc "echo INFO: remote connection successful" || die "ERROR: remote connection failed"

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
# What files to exclude from sync
cat > ${EXCLUDE_FILE} <<EOF
*mysqld-relay*
*relay-log.info
*mysql-bin.*
*master.info
EOF

# Check data directory location (locally, remote will actually be the snapshot location)
REMOTE_MYSQL_DIR=$(rc grep ^datadir $REMOTE_MYCNF | grep -oE "/.*"); [ -z "$REMOTE_MYSQL_DIR" ] && die "ERROR: remote mysql datadir could not be located"
echo "INFO: remote mysql datadir: $REMOTE_MYSQL_DIR"
REAL_MYSQL_DIR=$(awk '/^datadir/{ print $3 }' "$LOCAL_MYCNF"); [ -z "$REAL_MYSQL_DIR" ] && die "ERROR: local mysql datadir could not be located"
echo "INFO: local mysql datadir: $REAL_MYSQL_DIR"

# Check for mysql lvm partition ($0~v awk escape path slashes) # swap for local
LVM_MYSQL=$(df -P | awk '$0~v { print $1 }' v=$REAL_MYSQL_DIR); [ -z "$LVM_MYSQL" ] && die "ERROR: local mysql lvm partition could not be located"

# continue with snapshot process
# find srv partition and make sure at least ~5GB free space available # swap for local
LVM_SNAPSHOT=$(df -P | awk '/\/srv|lv_snapshots/ { print $1 }' | head -n 1); [ -z "$LVM_SNAPSHOT" ] && die "ERROR: /srv or ..lv_snapshots lvm partition could not be located"
if [[ $(df -Pm | awk '/\/srv|lv_snapshots/ { print $4 }' | head -n 1) -lt "$SNAPSHOT_FREESPACE" ]]; then # swap for local
  die "ERROR: Not enough free space for snapshot copy on write operations"
fi

# Ensure no snapshot exists # swap for local
echo "Confirming there are no existing snapshots...."
hcp -l | grep "No Hot Copy sessions" || { die "ERROR: Snapshot already exist, exiting..."; }

# Flush data to disk before transfer, create snapshot and resume # swap for local (and no need to specifiy host nor ssh)
# also get master coordinates
MASTER_LOG="/tmp/master.log"
echo "INFO: Connecting to source database..."

mysql << EOF
STOP SLAVE;
FLUSH TABLES WITH READ LOCK;
SYSTEM hcp $LVM_MYSQL -c $LVM_SNAPSHOT 2>&1 > /dev/null
SYSTEM mysql -B -N -e 'show master status' > $MASTER_LOG;
UNLOCK TABLES;
START SLAVE;
quit
EOF

echo "INFO: ### MASTER LOG DETAILS: `cat $MASTER_LOG`"

[ $? == 0 ] || { die "ERROR: Failed to stop slave, flush, create snapshot, unlock and start slave, log onto DB and check!!!!"; }

# swap for local - should probably rename, e.g. mysqldatadir_snapshot
SNAPSHOT_MYSQL_DIR=$(hcp -l | awk '/Mounted:/ { print $2 }') || { die "ERROR: Failed to locate snapshot mount point!"; }
echo "INFO: Snapshot volume: $SNAPSHOT_MYSQL_DIR"

FINAL_MYSQL_DIR="$SNAPSHOT_MYSQL_DIR"

MASTER_LOG_FILE=$(awk '{print $1}' $MASTER_LOG)
MASTER_LOG_POS=$(awk '{print $2}' $MASTER_LOG)
MASTER_IP=$(hostname -i | grep -oE "[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}")
MASTER_USER=$(sed -n '4p' ${SNAPSHOT_MYSQL_DIR}/master.info)
MASTER_PASS=$(sed -n '4p' ${SNAPSHOT_MYSQL_DIR}/master.info)

# do a clean mysql instance on datadir and shutdown
## get innodb_log_file_size 
INNODB_LOG_SIZE=$(mysqladmin variables | grep innodb_log_file_size | awk '{print $4}')
SNAPSHOT_SOCKET="/var/run/mysqld/mysqld-snapshot.sock"

mysqld_safe --no-defaults --port=3307 --socket="$SNAPSHOT_SOCKET" --datadir="$FINAL_MYSQL_DIR" --innodb-log-file-size="$INNODB_LOG_SIZE" --skip-slave-start &
sleep 10
mysqladmin --socket="$SNAPSHOT_SOCKET" shutdown || die "ERROR: error starting and shutting down mysql snapshot instance"

# Stop mysql remotely
rc service mysql stop
# clear remote mysql datadir
echo "INFO: clearing remote $REMOTE_MYSQL_DIR ..."
rc "rm -rf ${REMOTE_MYSQL_DIR}/*"

echo "INFO: Ready to sync..."

############# MAIN TASK ####################################################################
START_TIME=$(date)
echo "####################################################################"
echo "INFO: Starting sync..."
tar -cvf - -C "${FINAL_MYSQL_DIR}" --exclude-from="${EXCLUDE_FILE}" . \
| pv -s `du -sb "${FINAL_MYSQL_DIR}" | awk '{print $1}'` |
| ssh ${SSH_OPTIONS} "${SSH_USER}"@"${REMOTE_DB_SERVER}" "sudo tar -xf - -C $REMOTE_MYSQL_DIR"

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
rc chown mysql:mysql "${REMOTE_MYSQL_DIR}" -R

echo "INFO: Starting mysql..." # do remotely, seperate RD job
rc service mysql start ## DO REMOTELY ##
sleep 5 ## DO REMOTELY ##

# Restart again to catch remaining errors
rc service mysql restart # do remotely, seperate RD job ## DO REMOTELY ##
sleep 5

rcc 'mysqladmin flush-hosts'
rcc 'mysql -e "stop slave;"' || echo "WARNING: !!!! could not stop slave replication !!!!!!"
rcc 'mysql -e "reset slave all;"' || echo "WARNING: !!!! slave info could not be removed !!!!!!"
rc "CHANGE MASTER TO MASTER_HOST='${MASTER_IP}', MASTER_USER='${MASTER_USER}', MASTER_PASSWORD='${MASTER_PASS}', MASTER_LOG_FILE='${MASTER_LOG_FILE}', MASTER_LOG_POS=${MASTER_LOG_POS};"

rc 'mysql -e "start slave;"'

# check slave successfully running
rc 'mysql -e "show slave status \G"' | grep 'Running' | head -n 1 | grep -q 'Yes'
rc 'mysql -e "show slave status \G"' | grep 'Running' | tail -n 1 | grep -q 'Yes'

# if mysql version is higher then upgrade
[ "${MYSQL_VERSION_MASTER:2:1}" -lt "${MYSQL_VERSION_SLAVE:2:1}" ] && rc mysql_upgrade

exit 0
