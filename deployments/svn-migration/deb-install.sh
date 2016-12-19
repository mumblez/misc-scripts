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
  #/srv/cognolink/bin/inst cognolink-$project || die "ERROR: failed to install cognolink-$project"
  sudo aptitude --allow-untrusted --allow-new-upgrades --allow-new-installs -y -V install "cognolink-$project"  || die "ERROR: failed to install cognolink-$project"
  VS=`echo $* | grep '='`
  if [ -z "$VS" ]; then
    sudo aptitude --allow-untrusted --allow-new-upgrades -y -V reinstall "cognolink-$project"
  fi
done


exit 0