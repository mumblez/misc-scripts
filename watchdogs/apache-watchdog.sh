#!/bin/bash
# Script that checks whether apache is still up, and if not:
# - e-mail the last bit of log files
# - kick some life back into it
# -- Thomas, 20050606
# -- http://stackoverflow.com/questions/2168518/bash-script-to-restart-apache-automatically

PATH=/bin:/usr/bin
THEDIR=/srv/apache-watchdog
EMAILS="it-monitoring@***REMOVED***.com it-team@***REMOVED***.com"
#EMAILS="***REMOVED***@***REMOVED***.com"
#URLFILE="https://intranet.***REMOVED***.com/VERSION"
#use a php file instead as sometimes apache doesn't quite crash but hangs, still serves txt files but not php
URLFILE="https://intranet.***REMOVED***.com/_watchdog.php"
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
#if ( curl -s "$URLFILE" | grep "watchdog" ) && wget -O - "$URLFILE" 2>&1 | grep -i "200 OK"
if ( curl --connect-timeout 10 --max-time 15 -s "$URLFILE" | grep "watchdog" ) && wget --timeout=10 -O - "$URLFILE" 2>&1 | grep -i "200 OK"
then
    # we are up
    touch ~/.apache-was-up
else
        # write a nice e-mail
        echo -n "apache crashed at " > $THEDIR/mail
        date >> $THEDIR/mail
        echo >> $THEDIR/mail
        echo "Access log - Intranet:" >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        tail -n 400 /var/log/***REMOVED***/intranet/access_log >> $THEDIR/mail
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
        echo "Error log - apache:" >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        tail -n 200 /var/log/apache2/error.log >> $THEDIR/mail
        echo "###########################################################" >> $THEDIR/mail
        echo >> $THEDIR/mail
        echo "other vhosts access.log:" >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        tail -n 200 /var/log/apache2/other_vhosts_access.log >> $THEDIR/mail
        echo "###########################################################" >> $THEDIR/mail
        echo >> $THEDIR/mail
        echo "System Log:" >> $THEDIR/mail
        tail -n 200 /var/log/syslog >> $THEDIR/mail
        echo "###########################################################" >> $THEDIR/mail
        echo >> $THEDIR/mail
        echo "Process List:" >> $THEDIR/mail
        ps aux >> $THEDIR/mail
        echo "###########################################################" >> $THEDIR/mail

        # kick php52-fpm
        /etc/init.d/php52-fpm restart >> $THEDIR/mail 2>&1
        # kick apache
        echo "Now kicking apache - `date` ..." >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        /etc/init.d/apache2 stop >> $THEDIR/mail 2>&1
        killall -9 apache2 >> $THEDIR/mail 2>&1
	sleep 15
        /etc/init.d/apache2 start >> $THEDIR/mail 2>&1
	if [[ "$?" == 0 ]]; then
          echo "apache restarted - `date`" >> $THEDIR/mail
	else
	  echo "apache failed to restart - `date`" >> $THEDIR/mail
	  /etc/init.d/apache2 restart && echo "apache restarted (2nd try) - `date` " >> $THEDIR/mail
	fi
        echo "======================" >> $THEDIR/mail
        # send the mail
        echo >> $THEDIR/mail
        echo "Good luck troubleshooting!" >> $THEDIR/mail
        echo "======================" >> $THEDIR/mail
        #mail -s "Apache crashed and has been restarted on Production - web1 - `date`" $EMAILS < $THEDIR/mail
        echo "see attached logs" | mutt -s "Apache crashed and has been restarted on Production - web1 - `date`" $EMAILS -a $THEDIR/mail /tmp/apache-stats/apache-stats*
        rm ~/.apache-was-up
fi

# email using mutt to add attachments
# echo bla body | mutt -s "bla bla 222" ***REMOVED***@***REMOVED***.com ***REMOVED***@***REMOVED***.com -a abc.html apc.html

rm -rf $THEDIR
rm -f "$LOCKFILE"

exit 0
