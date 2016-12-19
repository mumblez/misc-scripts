#!/bin/bash

# We simply change the symlink to a previous release folder
# (note, the vendors directory is always shared so may have an impact)
# Relies on correct release provided by RD job and releases.json options script

die() { echo $* 1>&2 ; exit 1 ; }

RELEASE="@option.release@"
RELEASE_FOLDER="/srv/symfony/releases"
SYMFONY_ROOT="/somecomp/lib/php5/symfony2"
CURRENT_RELEASE=$(basename $(readlink $SYMFONY_ROOT))

# Validate
[ -d "${RELEASE_FOLDER}/${RELEASE}" ] || die "ERROR: Release folder $RELEASE_FOLDER does not exist!"

# Change symlink to old release
ln -snf "${RELEASE_FOLDER}/${RELEASE}" "${SYMFONY_ROOT}" && echo "INFO: Successfully rolled back to release (timestamp): $RELEASE" || die "ERROR: Failed to roll back to previous release folder"
