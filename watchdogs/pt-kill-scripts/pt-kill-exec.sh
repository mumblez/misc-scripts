#!/bin/bash

RETVAL=0

KILLLOG="/var/log/mysql-kill.log"
KILLLOGARCHIVE="/var/log/mysql-kill-archive.log"
EMAILS="ufFeBCh4HRBtmnVywr5269F1pQ2jtQ@api.pushover.net it-team@cognolink.com"
EMAIL_SUBJECT="Long Query Killed - Prod DB"
#EMAILS="yusuf.tran@cognolink.com"

( echo To: $EMAILS; echo From: admin@cognolink.com; echo Subject: $EMAIL_SUBJECT; echo; cat $KILLLOG  ) | sendmail -t;

# kill connection incase pt-kill doesn't kill
QID=$(head -n 1 $KILLLOG | awk '{print $5}')
mysqladmin kill $QID

cat $KILLLOG >> $KILLLOGARCHIVE; > $KILLLOG
