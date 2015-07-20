#!/bin/bash

die() { echo $* 1>&2 ; exit 1 ; }
PROJECTS="@option.projects@"

[ -z "$PROJECTS" ] && die "ERROR: no project(s) selected"


sudo aptitude clean
sudo aptitude update
if [ "$?" -ne 0 ]
then
  exit $?
fi

for project in $PROJECTS; do
  echo "INFO: installing $project ..."
  #/srv/***REMOVED***/bin/inst ***REMOVED***-$project || die "ERROR: failed to install ***REMOVED***-$project"
  sudo aptitude --allow-untrusted --allow-new-upgrades --allow-new-installs -y -V install "***REMOVED***-$project"  || die "ERROR: failed to install ***REMOVED***-$project"
  VS=`echo $* | grep '='`
  if [ -z "$VS" ]; then
    sudo aptitude --allow-untrusted --allow-new-upgrades -y -V reinstall "***REMOVED***-$project"
  fi
done


exit 0