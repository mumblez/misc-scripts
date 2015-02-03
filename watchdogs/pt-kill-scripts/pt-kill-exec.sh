#!/bin/bash

RETVAL=0

KILLLOG="/var/log/mysql-kill.log"
KILLLOGARCHIVE="/var/log/mysql-kill-archive.log"
#EMAILS="***REMOVED*** it-team@***REMOVED***.com"
EMAILS="***REMOVED***@***REMOVED***.com"

#pt-kill \
#  --no-version-check \
#  --busy-time 10s \
#  --ignore-info '(?i-smx:^insert|^update|^delete|^load|mailqueue)' \
#  --match-info '(?i-xsm:select)' \
#  --match-user '(?i-xsm:***REMOVED***)' \
#  --print \
#  --kill-query \
#  --execute-command "( echo To: $EMAILS; echo From: admin@***REMOVED***.com; echo Subject: 'Long Query Killed - Prod DB'; echo; cat /var/log/mysql-kill.log  ) | sendmail -t; echo hello; echo blabla; echo zzz"
#


( echo To: $EMAILS; echo From: admin@***REMOVED***.com; echo Subject: 'Long Query Killed - Prod DB'; echo; cat /var/log/mysql-kill.log  ) | sendmail -t;

# kill connection incase pt-kill doesn't kill
QID=$(head -n 1 $KILLLOG | awk '{print $5}')
mysqladmin kill $QID

cat $KILLLOG >> $KILLLOGARCHIVE; > $KILLLOG
