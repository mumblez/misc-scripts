#!/bin/bash

# High level meta job to co-ordinate 
# -pulling from web server, 
# -transferring to db server
# -executing on db server.
# script to be run from rundeck directly

WEB_SERVER="@option.web_frontend@" # can use $(hostname)
DB_SERVER="@option.db_backend@" # have to map to correct hostname of db server
#EXEC_JOB_ID="bb2c2b76-4901-46f0-9719-6a17184a058b" # https://***REMOVED***.***REMOVED***.com/project/Everything/jobs/snippets/misc/deployments/phase1 (6-eventLogTriggers-run)
TRIGGERS_FILE="/tmp/triggers.sql"
RUNDECK_USER="rundeck"

# Pull from web server
scp -o StrictHostKeyChecking=no "${RUNDECK_USER}@${WEB_SERVER}:${TRIGGERS_FILE}" /tmp

# Push to db server
scp -o StrictHostKeyChecking=no "${TRIGGERS_FILE}" "${RUNDECK_USER}@${DB_SERVER}:/tmp"

rm -f "$TRIGGERS_FILE"


# Execute script on db server
# call another RD job, which itself set's HOME=/***REMOVED*** and runs the triggers.sql file
# job should be called with sudo

#run -i $EXEC_JOB_ID -F -- -host "$DB_SERVER"
