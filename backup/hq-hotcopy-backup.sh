#!/bin/bash

die() { echo $* 1>&2 ; exit 1 ; }

HOT_COPY_DIRS="/srv/r5/hq/FinanceDBs /srv/r5/hq/fileserver /srv/r5/hq/marketing /srv/r5/hq/***REMOVED***"
#HOT_COPY_DIRS="/srv/r5/hq/marketing /srv/r5/hq/***REMOVED***"
ZB_REPO="/srv/r5/backups/zbackup-repos/hq-fileserver"
ZB_KEY="/***REMOVED***/keys/zbackup"

# add check for zbackup binary
test -x /usr/local/bin/zbackup && ZB_BIN="/usr/local/bin/zbackup" || ZB_BIN="/bin/zbackup"
test -x $ZB_BIN || ZB_BIN="/usr/bin/zbackup"

[ -d "$ZB_REPO" ] || die "ERROR: Repo - $ZB_REPO not found"

for HC in $HOT_COPY_DIRS;
do
  APP=$(basename $HC);
  FILE_DATE=$(date +%Y-%m-%d)
  BACKUP_FILE="${ZB_REPO}/backups/${APP}/daily/${APP}-${FILE_DATE}.tar"
  echo "INFO: making zbackup of $APP... - `date`"
  tar -cf - -C "$HC" . | "$ZB_BIN" --password-file "$ZB_KEY" backup "$BACKUP_FILE" || die "ERROR: $APP Backup failed"
  echo "INFO: backup of $APP sucessfully completed - `date`"
done

echo "INFO: hq fileserver backups successful"
exit 0
