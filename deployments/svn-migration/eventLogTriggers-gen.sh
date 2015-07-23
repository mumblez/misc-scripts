#!/bin/bash
# Generate on web

die() { echo $* 1>&2 ; exit 1 ; }
### Settings ###
PHP="/usr/local/php52/bin/php"
CL_ROOT="/***REMOVED***"
EVENTLOGTRIGGERS_SCRIPT="${CL_ROOT}/bin/eventLogTriggers.php"
DB_PROPERTIES="${CL_ROOT}/config/intranet/db.properties"
DB_SERVER=$(grep 'DB_HOST=' "$DB_PROPERTIES" | head -n 1 | cut -d'=' -f2)
SQL_OUTPUT_FILE="/tmp/triggers.sql"
TRIGGER_CONFIG="${CL_ROOT}/lib/php5/***REMOVED***/common/prototypes/eventlog/configuration.properties"

### Validate ####
[[ -f "$PHP" && -x "$PHP" ]] || die "ERROR: php 5.2 binary not found"
[ -d "$CL_ROOT" ] || die "ERROR: $CL_ROOT not found"
[ -f "$EVENTLOGTRIGGERS_SCRIPT" ] || die "ERROR: $EVENTLOGTRIGGERS_SCRIPT not found"
[ -f "$DB_PROPERTIES" ] || die "ERROR: $DB_PROPERTIES not found"
[ -f "$TRIGGER_CONFIG" ] || die "ERROR: $TRIGGER_CONFIG not found"

echo "INFO: Generating triggers.sql..."

 $PHP $EVENTLOGTRIGGERS_SCRIPT \
  --db-config=$DB_PROPERTIES \
  --output=$SQL_OUTPUT_FILE \
  --trigger-config=$TRIGGER_CONFIG \
  --recreate-procedure \
  --drop-triggers-for-database=***REMOVED***,cognoweb \
  --create-triggers &>/dev/null && echo "$SQL_OUTPUT_FILE successfully produced" || die "ERROR: Failed to produce $SQL_OUTPUT_FILE"


# rm -f $SQL_OUTPUT_FILE
exit 0