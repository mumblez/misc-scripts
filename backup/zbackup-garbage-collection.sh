#!/bin/bash

<<INTRO
	As we rotate dailies, weeklies the zbackup data bundles still exist and take up unnecessary
	space, so we run "zbackup gc" on our repo's to do some cleanup, operation takes a few hours!
INTRO

die() { echo $* 1>&2 ; exit 1 ; }

ZB_REPOS_BASE="/srv/r5/backups/zbackup-repos"
ZB_KEY="/***REMOVED***/keys/zbackup"
ZB_BIN="/usr/local/bin/zbackup"
ZB_ARGS="--password-file $ZB_KEY --cache-size 1024mb"
DIRECTORIES="ZB_REPOS_BASE ZB_KEY ZB_BIN"

for directory in $DIRECTORIES; do
	[ -e "${!directory}" ] || die "ERROR: $directory can not be found."
done

# main 

cd "$ZB_REPOS_BASE"
for ZDIR in $(ls);
do
	echo "### Starting - $(date) ###"
	"$ZB_BIN" $ZB_ARGS gc "$ZDIR" || die "ERROR: zbackup gc of $ZDIR repo failed."
	echo "### Finished - $(date) ###"
done

exit 0