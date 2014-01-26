#!/bin/bash
LIVE_SLAVE='live-slave-db.corp.***REMOVED***.com'
DBS=( ***REMOVED*** cognoweb cognoprofiles file_repository geo )
AUTH_FILE2="/***REMOVED***/.my.cnf.backup"
AUTH_FILE="/***REMOVED***/.my.cnf"
AUTH2="--defaults-file=$AUTH_FILE2"
AUTH="--defaults-file=$AUTH_FILE"
DUMP_OPTS="--add-drop-database --add-drop-table --no-data --single-transaction --skip-triggers --default-character-set=utf8"
DATA_DUMP_OPTS="--no-create-db --no-create-info --no-autocommit --routines --skip-triggers --extended-insert --single-transaction --max_allowed_packet=256M"
TRIGGER_DUMP_OPTS="--no-create-db --no-create-info --no-data --triggers --extended-insert --single-transaction"
OPS='schema data triggers'
EXCLUDE_OPT=""
EXCLUDE_LIST="services service_configuration scheduled_task"
RUN_LOG=/tmp/run.log

# Check if first run
if [ -e "${RUN_LOG}" ]; then
    FIRST_RUN='false'
else
    FIRST_RUN='true'
fi

### Prepare functions ###

# Backup or Restore qa / test specific tables
qatables () {
	for TABLE in $EXCLUDE_LIST; do
		if [ "$TABLE" != "eventlog" ] && [ "$TABLE" != "commlog" ] && [ "$TABLE" != "emaillog" ]; then
			if [ "$1" == "backup" ]; then
				echo "Backing up ***REMOVED***.$TABLE...$(date)"
				mysqldump "$AUTH" -B ***REMOVED*** --tables "$TABLE" --create-option > /tmp/***REMOVED***."$TABLE".sql
			elif [ "$1" == "restore" ]; then
				echo "Restoring ***REMOVED***.$TABLE...$(date)"
				mysql "$AUTH" -B ***REMOVED*** < /tmp/***REMOVED***."$TABLE".sql
			fi
		fi
	done
}

# Backup and Restore operations for complete DBs
# If we successfully restore the data (biggest dump as triggers and schema are very small) then we logged to run.log file
# If / When if crashes and we re-run this script than it should ignore the ones we've successfully logged and continue
# with remaining DBs.
# NOTE, in the unlikely case that a data restore succeeds but the triggers import fails then it's possible we'd 
# miss it the next run
mysqlop () {
	for op in $OPS; do
		echo "$1 ${op}...$(date)"
			FILE=/var/lib/mysql/temp-"$1"-"${op}".db

			if ! [ -e "${FILE}" ]; then
				echo "Dumping $1 ${op} to ${FILE}...$(date)"
				case "${op}" in
					schema)
						mysqldump ${AUTH2} -h ${LIVE_SLAVE} ${DUMP_OPTS} $1 > ${FILE}
						;;
					data)
						mysqldump ${AUTH2} -h ${LIVE_SLAVE} ${DATA_DUMP_OPTS} ${EXCLUDE_OPT} $1 > ${FILE}
						;;
					triggers)
						mysqldump ${AUTH2} -h ${LIVE_SLAVE} ${TRIGGER_DUMP_OPTS} $1 > ${FILE}
						;;
				esac
			fi

			if [ "$?" == 0 ]; then
				echo "Restoring $1 ${op} from ${FILE}...$(date)"
				if ! grep -Fxq "$db-${op}-COMPLETE" "$RUN_LOG"; then
					mysql "$AUTH" "$1" < "${FILE}"
					if [ "$?" == 0 ]; then
						echo "Restore successful and deleting ${FILE}...$(date)"
						rm -rf "${FILE}"
						echo "$1-${op}-COMPLETE" >> "${RUN_LOG}"
					else
						echo "Restore failed (${FILE} remains)...$(date)"
					fi
				else
					echo "$db-${op} already restored"
				fi
			else
				echo "Restore of $1 - ${op} failed...$(date)"
			fi
	done
}

mysql_settings_save () {
    DBNETWRITE=$(mysql -e 'SELECT @@GLOBAL.net_write_timeout \G' | grep "GLOBAL" | awk '{print $2}')
    DBNETREAD=$(mysql -e 'SELECT @@GLOBAL.net_read_timeout \G' | grep "GLOBAL" | awk '{print $2}')
    DBFKCHECK=$(mysql -e 'SELECT @@GLOBAL.foreign_key_checks \G' | grep "GLOBAL" | awk '{print $2}')
    echo "DBNETWRITE=$DBNETWRITE" > "$RUN_LOG"
    echo "DBNETREAD=$DBNETREAD" >> "$RUN_LOG"
    echo "DBFKCHECK=$DBFKCHECK" >> "$RUN_LOG"
}

mysql_settings_apply () {
    # Increase timeouts and turn off foreign key checks
    mysql -e 'use mysql; repair table proc;' > /dev/null 2>&1
    mysql -e 'SET GLOBAL net_write_timeout=600; SET GLOBAL net_read_timeout=600; SET GLOBAL foreign_key_checks=0;'
}

db_dump_and_restore () {
    for DB in ${DBS[@]}; do
        for TABLE in $EXCLUDE_LIST; do
                EXCLUDE_OPT="$EXCLUDE_OPT--ignore-table=$DB.$TABLE "
        done
        mysql -e 'use mysql; repair table proc;' > /dev/null
        echo "Importing ${DB} from live-slave to staging...$(date)"
        mysql "$AUTH" -e "drop database ${DB}; create database ${DB}"
        mysqlop "$DB"
        echo "-----------------------------------------------------------------------"
        echo "-----------------------------------------------------------------------"
        EXCLUDE_OPT=''
        echo "${DB} Done."
    done
}

amend_db_list () {
    for db in ${DBS[@]}; do
		# if last db operation complete, remove from db list
        if grep -Fxq "$db-triggers-COMPLETE" "$RUN_LOG"; then
            DBS=( ${DBS[@]/$i/} )
            echo "=== SKIPPING $db data ==="
        fi
    done
}

amend_mysql_properties_to_restore () {
    DBNETWRITE=$(grep "DBNETWRITE" $RUN_LOG | cut -d'=' -f 2)
    DBNETREAD=$(grep "DBNETREAD" $RUN_LOG | cut -d'=' -f 2)
    DBFKCHECK=$(grep "DBFKCHECK" $RUN_LOG | cut -d'=' -f 2)

}

# Main

# Start mysql incase it crashed
/etc/init.d/mysql start

if [ "${FIRST_RUN}" == "true" ]; then
    mysql_settings_save
    qatables backup
    mysql_settings_apply
else
    echo "=== RE-RUN ==="
    amend_db_list
    amend_mysql_properties_to_restore
fi

db_dump_and_restore
qatables restore

# Restore original mysql timeout values and foreign key check
mysql -e "SET GLOBAL net_write_timeout=${DBNETWRITE}; SET GLOBAL net_read_timeout=${DBNETREAD}; SET GLOBAL foreign_key_checks=${DBFKCHECK};"
mail -s "Test DB restored" snookermad@gmail.com < "$RUN_LOG"
rm -rf "${RUN_LOG}"
echo -e "DONE!---$(date)"
exit 0