#!/bin/bash
# Name:		MySQL_REBUILD_LIVE_SLAVE_from_MASTER
# Purpose:	Rebuilds live all Databases of a replication SLAVE based on a good running MASTER
#		This rebuilt action is done without stopping the MASTER MySQL server or even locking the tables
#		or the destination server (SLAVE)
# Syntax:	MySQL_REBUILD_LIVE_SLAVE_from_MASTER Master:Port Slave:Port {F|P}
#		eg. MySQL_REBUILD_LIVE_SLAVE_from_MASTER db1:3306 www1:3306 P
#               {F|P} - Dump method     F) Uses a full temporary dump file method     P) Uses the pipe method
#               Note: In some situation where the databases are very big (GB) the Pipe (P) method migh not work well
#                     In these casse it is recommended to use the File(F) method
# Changes:	05 Dec 2008	First implementation of script
#               10 Oct 2013     Added the File(F) transfer method, added --skip-lock-tables to the dump command, added the manual entry of ***REMOVED*** PW
# Author:	Michel Bisson (michel@itmatrix.de)
# Notes 1:	In the case of using the Dump file method, the file will be transfered via rsync to the slave for importing.
#               Therefore the key of the user running the script must be already installed in slave before running the script
#-----------------------------------------------------------------------------------
# Some constants:
DUMPFILE="/srv/live-dump.db"
# Resync the databases except the following Databases
EXCEPTIONS="information_schema mysql test"
#
# Functions
# Syntax: testhost addr port. Returns: hostOK=1
testhost () {
    hostOK=0
    if (nmap -n --host_timeout 1600 --max_rtt_timeout 1600 -p $2 -P0 $1 2>/dev/null | grep -q "open" &>/dev/null); then
	hostOK=1
    fi
};
#
usage () {
    echo "ERROR: Somethig is wrong with the given arguments"
    echo "Syntax: MySQL_REBUILD_LIVE_SLAVE_from_MASTER Master:Port Slave:port {F|P}"
    echo "    eg. MySQL_REBUILD_LIVE_SLAVE_from_MASTER master1:3306 slave1:3306 P"
    exit 1
}
#
# Check the command syntax
if [ $# -ne 3 ]; then
    usage
fi
#
# Get the mysql ***REMOVED*** password
echo -n "Please enter the MySQL ***REMOVED*** password: " ; read $***REMOVED***pw
#
#- Check the hosts info validity
if ! (echo $1 | grep ':'); then
    echo "ERROR: The 2nd parameter(master) must be the combination 'host:port'"
    exit 3
fi
#
if ! (echo $2 | grep ':'); then
    echo "ERROR: The third parameter must be the combination 'host:port'"
    exit 4
fi
#
method=$3
#
# Check the hosts connectivity of master host
Mhost=$(echo $1 | cut -d: -f1)
Mport=$(echo $1 | cut -d: -f2)
#
testhost $Mhost $Mport
if [ $hostOK = "0" ]; then
    echo "ERROR: The master $Mhost:$Mport does not respond"
    exit 5
fi
#
# Check the hosts connectivity of slave host
#
Shost=$(echo $2 | cut -d: -f1)
Sport=$(echo $2 | cut -d: -f2)
#
testhost $Shost $Sport
if [ $hostOK = "0" ]; then
    echo "ERROR: The slave $Shost:$Sport does not respond"
    exit 6
fi
#

# Stop and reset the slave
echo "STOP SLAVE; RESET SLAVE;" | mysql -h $Shost --port=$Sport -u ***REMOVED*** --password=$***REMOVED***pw

#

databases=""

for DB in $(echo "show databases;" | mysql -h $Shost --port=$Sport -u ***REMOVED*** --password=$***REMOVED***pw | grep -v Database) ; do
    # Only delete/add the databases that are not in the Exceptions list
    if ! (echo $EXCEPTIONS | grep -q $DB); then
        # here I was deleting the databases one by one before recreating them in slave
        # I replaced this by the option --add-drop-database in mysqldump
	#echo "Deleting database $DB on Slave $Shost:$Sport"
	#echo "DROP DATABASE $DB;" | mysql -h $Shost --port=$Sport -u ***REMOVED*** --password=$***REMOVED***pw
		if [ $databases = "" ]; then
			databases=$DB
		else
			databases=$databases,$DB
		fi
    fi
done

#

case $method in

    P)	# Transfer all databases from master to slave directly using a pipe(P)
	echo "Transfering the all databases from master $Mhost:$Mport into slave $Shost:$Sport directly"
	mysqldump -h $Mhost --port=$Mport -u ***REMOVED*** --password=$***REMOVED***pw \
	--single-transaction --flush-logs --master-data=2 --skip-lock-tables \
	--add-drop-database --delete-master-logs --hex-blob --databases $databases \
	| mysql -h $Shost --port=$Sport -u ***REMOVED*** --password=$***REMOVED***pw
    ;;

#

    F)  # Transfer the databases using a dump file
	echo "Dumping the all databases from master $Mhost:$Mport into file $DUMPFILE"
	mysqldump -h $Mhost --port=$Mport -u ***REMOVED*** --password=$***REMOVED***pw \
	--single-transaction --flush-logs --master-data=2 --skip-lock-tables \
	--add-drop-database --delete-master-logs --hex-blob --databases $databases > $DUMPFILE

#
	echo "Transferring the dump file $DUMPFILE from Master $Mhost to slave $Shost via compressed rsync"
	rsync -vz $DUMPFILE $Shost:$DUMPFILE
	echo "Importing the dump file ($DUMPFILE) into slave MySQL server $Shost"
	ssh $Shost "mysql -h $Shost --port=$Sport -u ***REMOVED*** --password=$***REMOVED***pw < $DUMPFILE"
    ;;

#
    *) usage ;;

esac

#
# Find out the master binlog file name
masterlogfile=$(echo "SHOW MASTER STATUS\G;" | mysql --host=$Mhost --port=$Mport -u ***REMOVED*** --password=$***REMOVED***pw | grep "File:" | cut -d: -f2 | cut -d" " -f2)
#
# Sync the slave with master binlog position 4
echo "CHANGE MASTER TO master_log_file='$masterlogfile',master_log_pos=4;" | mysql -h $Shost --port=$Sport -u ***REMOVED*** --password=$***REMOVED***pw
#

# Start the replication on slave

echo "START SLAVE;" | mysql -h $Shost --port=$Sport -u ***REMOVED*** --password=$***REMOVED***pw
sleep 3

#

# Show slave status to see if all is in sync

echo "SHOW SLAVE STATUS \G;" | mysql -h $Shost --port=$Sport -u ***REMOVED*** --password=$***REMOVED***pw