#!/bin/bash
#
# pt-kill   This shell script takes care of starting and stopping
#               the pt-kill services.
#
# chkconfig: - 60 20
# description: pt-kill stops long running MySQL queries
#
# probe: true

# Source function library.
. /lib/lsb/init-functions
#. /etc/rc.d/init.d/functions

RETVAL=0

KILLLOG="/var/log/mysql-kill.log"
KILLLOGARCHIVE="/var/log/mysql-kill-archive.log"
# See how we were called.
case "$1" in
  start)
    echo -n $"Starting pt-kill: "

    pt-kill \
      --pid /var/run/pt-kill.pid \
      --daemonize \
      --interval 30s \
      --busy-time 3600s \
      --wait-after-kill 15s  \
      --ignore-info '(?i-smx:^insert|^update|^delete|^load|mailqueue)' \
      --match-info '(?i-xsm:select)' \
      --ignore-user '(?i-xsm:***REMOVED***)' \
      --match-user '(?i-xsm:sqluser)' \
      --log "$KILLLOG" \
      --print \
      --execute-command "( echo To: it-monitoring@***REMOVED***.com; echo From: admin@***REMOVED***.com; echo Subject: 'Long Query Killed'; echo; cat /var/log/  mysql-kill.log) | sendmail -t; cat $KILLLOG >> $KILLLOGARCHIVE; > $KILLLOG" \
      --kill-query

    RETVAL=$?
    echo
    [ $RETVAL -ne 0 ] && exit $RETVAL

  ;;
  stop)
        # Stop daemons.
        echo -n $"Shutting down pt-kill: "
        #killproc pt-kill
        kill -9 $(ps aux | grep pt-kill | head -n1 | awk '{ print $2 }')
        rm -f /var/run/pt-kill.pid
        echo
    ;;
  restart)
    $0 stop
        $0 start
        ;;
  *)
        echo $"Usage: pt-kill {start|stop}"
        RETVAL=3
        ;;
esac

exit $RETVAL
