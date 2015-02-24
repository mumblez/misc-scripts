#!/bin/bash

RETVAL=0

KILLLOG="/var/log/mysql-kill.log"
KILLLOGARCHIVE="/var/log/mysql-kill-archive.log"
EMAILS="***REMOVED*** it-team@***REMOVED***.com"
EMAIL_SUBJECT="Long Query Killed - Prod DB"
#EMAILS="***REMOVED***@***REMOVED***.com"

( echo To: $EMAILS; echo From: admin@***REMOVED***.com; echo Subject: $EMAIL_SUBJECT; echo; cat $KILLLOG  ) | sendmail -t;

# kill connection incase pt-kill doesn't kill
QID=$(head -n 1 $KILLLOG | awk '{print $5}')
mysqladmin kill $QID

cat $KILLLOG >> $KILLLOGARCHIVE; > $KILLLOG
