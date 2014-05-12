#!/bin/bash
# Script that checks whether apache is still up, and if not:
# - e-mail the last bit of log files
# - kick some life back into it
# -- Thomas, 20050606
# -- http://stackoverflow.com/questions/2168518/bash-script-to-restart-apache-automatically

PATH=/bin:/usr/bin
THEDIR=/srv/apache-watchdog
EMAILS="it-monitoring@***REMOVED***.com"
#EMAILS="***REMOVED***@***REMOVED***.com"
#URLFILE="https://intranet.***REMOVED***.com/VERSION"
#use a php file instead as sometimes apache doesn't quite crash but hangs, still serves txt files but not php
URLFILE="https://intranet.***REMOVED***.com/_watchdog.php"
#web 1 public IP = 92.52.113.224
LOCKFILE="/tmp/apacheCheck"

if [ -e "$LOCKFILE" ]; then
  exit 0;
else
  touch "$LOCKFILE"
fi

mkdir -p $THEDIR

if [ ! -e /***REMOVED***/www/intranet/_watchdog.php ]; then
  echo '<?php echo "watchdog" ?>' > /***REMOVED***/www/intranet/_watchdog.php
fi

#if ( wget --timeout=30 -q -P "$THEDIR" "$URLFILE" )
if ( curl -s "$URLFILE" | grep "watchdog" ) && wget --timeout=10 -O - "$URLFILE" 2>&1 | grep -i "200 OK"
then
    # we are up
    touch ~/.apache-was-up
else
    if [ -e ~/.apache-was-up ];
    then
        # write a nice e-mail
        echo -n "apache crashed at " > $THEDIR/mail
        date >> $THEDIR/mail
        echo >> $THEDIR/mail
        echo "Access log - Intranet:" >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        tail -n 200 /var/log/***REMOVED***/intranet/access_log >> $THEDIR/mail
        echo "###########################################################" >> $THEDIR/mail
        echo >> $THEDIR/mail
        echo "Access log 1 - Website:" >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        tail -n 200 /var/log/***REMOVED***/website/access_log >> $THEDIR/mail
        echo "###########################################################" >> $THEDIR/mail
        echo >> $THEDIR/mail
#        echo "Access log 1 - Website:" >> $THEDIR/mail
#        tail -n 100 /var/log/***REMOVED***/intranet/access.log >> $THEDIR/mail
        echo >> $THEDIR/mail
        echo "Error log - Intranet:" >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        tail -n 200 /var/log/***REMOVED***/intranet/error_log >> $THEDIR/mail
        echo "###########################################################" >> $THEDIR/mail
        echo >> $THEDIR/mail
        echo "Error log - Website:" >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        tail -n 200 /var/log/***REMOVED***/website/error_log >> $THEDIR/mail
        echo "###########################################################" >> $THEDIR/mail
        echo >> $THEDIR/mail
        # kick apache
        echo "Now kicking apache..." >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        /etc/init.d/apache2 stop >> $THEDIR/mail 2>&1
        killall -9 apache2 >> $THEDIR/mail 2>&1
        /etc/init.d/apache2 start >> $THEDIR/mail 2>&1
        echo "apache restarted"
        echo "======================" >> $THEDIR/mail
        # send the mail
        echo >> $THEDIR/mail
        echo "Apache restarted - Good luck troubleshooting!" >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        mail -s "Apache crashed and has been restarted on Production - web1" $EMAILS < $THEDIR/mail
        rm ~/.apache-was-up
    fi
fi

rm -rf $THEDIR
rm -f "$LOCKFILE"

exit 0
