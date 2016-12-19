innobackupex
============

Setup
-----

Create base directory where backups will live and run the init-inno-setup.sh script to setup the directories
and initial full backups.

Assumes zbackup and xtrabackup is already setup and log folders created under /var/log/{innobackupex,zbackup}

Add the crons if not already added, e.g.

# mysql backup
# incremental
00 * * * *	root	/root/scripts/mysql-backup.sh incremental &>> /var/log/innobackupex/incremental-backup.log
# full
15 23 * * *	root	/root/scripts/mysql-backup.sh full &>> /var/log/innobackupex/full-backup.log


NOTES
=====

USE init-inno... script to initialise innodb directories

--extra-lsndir = put lsn start stop numbers in this directory (last checkpoint)
--incremental-basedir = can read the same dir as above (save searching for last / most recent
backup / last checkpoint)


full / hotcopy backup (and prepare for incrementals)
----------------------------------------------------
```innobackupex --no-timestamp --extra-lsndir /srv/r5/backups/mysql-innobackupex/last-checkpoint /srv/r5/innobackupex/mysql-hotcopy && innobackupex --apply-log --redo-only /srv/r5/backups/mysql-innobackupex/mysql-hotcopy && cp -ar /srv/r5/backups/mysql-innobackupex/mysql-hotcopy /srv/r5/backups/mysql-innobackupex/realised```

incrementals
------------
```innobackupex --incremental --extra-lsndir /srv/r5/backups/mysql-innobackupex/last-checkpoint --incremental-basedir /srv/r5/backups/mysql-innobackupex/last-checkpoint /srv/r5/backups/mysql-innobackupex/incrementals```

(create and check for locks, likely to overrun an hour in future)


times
=====
full backup = 3:30pm - 3:52pm = 22mins (159GB)
incremental = 4:16pm - 4:39pm = 23mins (wtf??? 103MB)
incremental with parallel=8 (and implicit compression) = 4:43pm - 4:57 = 14mins (64MB)
(apply-log is very quick, minute)

zbackup (lzo)
-------------
zbackup 1st run (lzo)= 5:50pm - 01:51am = 8 hours (93GB hmmmm)
zbackup 2nd run (lzo)= 11:58am - 13:16pm = 1hr 18mins (less than 1GB)
uncompress time = 2:25pm - 2:55pm (very fast, 45GB after 5 minutes) - still have to untar ~20mins, diff -q <orig dir> <restored backup> worked

zbackup (lzma - default)
------------------------
zbackup 1st run (lzma - should be much longer than lzo)= 15:45 - 20:19 = 4hrs 34mins (83GB)  
zbackup 2nd run (lzma)= 
uncompress time = 

Use lzma as it's multi-threaded!!!


zbackup commands
================
backup - ```START=$(date); tar -cf - -C /srv/r5/backups/mysql-innobackupex/mysql-hotcopy . | zbackup --password-file /root/keys/zbackup backup /srv/r5/backups/zbackup-repo/backups/<something....with...date>.tar```

(best to cd to directory and tar else restore looks confusing)
DO NOT COMPRESS OR ENCRYPT FILES AHEAD OF TIME else will alleviate benefit of deduplication
(defaults to 16 threads if needed, add cache setting when extracting but no larger than a couple gig)

restore - ```START=$(date); date; zbackup --cache-size 3000mb --password-file /root/keys/zbackup restore <backup to restore>.tar | tar -xf - -C /path/to/extract/to; echo "start: $START"; echo "end: $(date)"; echo "zbackup restore test complete" | mail -s "zbackup restore test complete" yusuf.tran@cognolink.com```


prune old backups (bundle files)
--------------------------------
```zbackup --non-encrypted gc /srv/r5/backups/zbackup-repo```

delete or archive old backups and prune, the real data is in bundles but only delete hash reference
files in 'backup' directory under zbackup-repo

md5sum / compare directories
diff <(find <dir1> -type f -print0 | xargs -0 md5sum | awk '{print $1}') <(find <dir2> -type f -print0 | xargs -0 md5sum | awk '{print $1}')

or simply

diff -q <dir1> <dir2>
(will only report if files are different and exit 1)
