#!/bin/bash

# runs livedata update and updates team if new changes detected or sync failed.
# should be called from cron

FS_BIN="/srv/packages/revere-livedata-1.11.21/livedata"
FS_LOG="/var/log/factset_livedata_sync.log"
FS_TMP_LOG="/tmp/factset_update.log"
EMAILS="***REMOVED***@***REMOVED***.com ***REMOVED***@***REMOVED***.com ***REMOVED***@***REMOVED***.com"


$FS_BIN > $FS_TMP_LOG 2>&1
cat $FS_TMP_LOG >> $FS_LOG

if ! tail -n 1 $FS_TMP_LOG | grep -q 'Updating completed.'; then 
	cat $FS_TMP_LOG | mail -s "FactSet LiveData sync failure" it-monitoring@***REMOVED***.com
else
	if ! tail -n -2 $FS_TMP_LOG | head -n 1 | grep -q 'Nothing to update'; then 
		cat $FS_TMP_LOG | mail -aFrom:admin@***REMOVED***.com -s "FactSet LiveData updated with changes" $EMAILS
	fi
fi

exit 0