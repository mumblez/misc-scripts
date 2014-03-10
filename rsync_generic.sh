#/bin/bash
# pull / sync files from remote server as source, local server where we initiate this script is destination

# SETTINGS #
LOCAL_DIR=@option.local_dir@
REMOTE_DIR=@option.remote_dir@
DIR=$(cd "$(dirname "$0")" && pwd)
SSH_USER=@option.ssh_user@
REMOTE_SERVER=@option.remote_host@

# FUNTIONS
die() { echo $* 1>&2 ; exit 1 ; }

rc () {
  ssh ${SSH_USER}@${REMOTE_SERVER} $@ || { die "Failed executing - $@ - on ${REMOTE_SERVER}"; }
}

# VALIDATION #
[ -d "$LOCAL_DIR" ] || die "ERROR: $LOCAL_DIR not found"
rc "echo ssh login test" > /dev/null || die "ERROR: can not ssh to $REMOTE_SERVER"
rc test -d "$REMOTE_DIR" || die "ERROR: $REMOTE_DIR does not exist"

# MAIN #
rsync -arv --inplace --delete "${SSH_USER}@${REMOTE_SERVER}:${REMOTE_DIR}/" "${LOCAL_DIR}/" || die "ERROR: could not rsync directories"

# FINISH #
exit 0
