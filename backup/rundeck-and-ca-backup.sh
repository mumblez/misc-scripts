#!/bin/bash

# SETTINGS
DIR=$(cd "$(dirname "$0")" && pwd)
SSH_USER="rundeck"
SSH_OPTIONS="-o StrictHostKeyChecking=no"
SSH_KEY="/var/lib/rundeck/.ssh/id_rsa"
REMOTE_SERVER="***REMOVED***.209"
ZB_REPOS_BASE_REMOTE="/srv/r5/backups/zbackup-repos"
ZB_REPO_REMOTE="${ZB_REPOS_BASE_REMOTE}/files"
ZB_KEY_REMOTE="/***REMOVED***/keys/zbackup"
ZB_INFO_REMOTE="${ZB_REPO_REMOTE}/info"
ZB_APP_NAME="rundeck_and_ca"
CA_DIR="/srv/ca"
JOBS="/tmp/backup/everything-jobs.yaml"
DB="/tmp/backup/rd-db.sql"
RD_PROJECTS="/var/rundeck/projects"
ARCHIVE="/srv/backups/rundeck-and-ca-`date +%Y-%m-%d`.tar"
ZB_BIN="/usr/local/bin/zbackup"
ZB_REPO="/srv/zbtemp"
ZB_KEY="/srv/zbackup"
ZB_INFO="/srv/info"

# run local backups
echo "INFO: Backing up Rundeck and CA..."
rd-jobs list -p Everything -f "$JOBS" --format yaml &>/dev/null
/usr/bin/mysqldump --defaults-file=/***REMOVED***/.my.cnf -B rundeck > "$DB"
tar -cf "$ARCHIVE" "$JOBS" "$DB" --remove-files &>/dev/null
tar --append --file="$ARCHIVE" "$RD_PROJECTS"
tar --append --file="$ARCHIVE" "$CA_DIR"

# pull zbackup key and info from backup
echo "INFO: pull zbackup keys"
rsync -ar -e "ssh -i $SSH_KEY" --rsync-path="sudo rsync" "${SSH_USER}"@"${REMOTE_SERVER}":"${ZB_INFO_REMOTE}" "$ZB_INFO"
rsync -ar -e "ssh -i $SSH_KEY" --rsync-path="sudo rsync" "${SSH_USER}"@"${REMOTE_SERVER}":"${ZB_KEY_REMOTE}" "$ZB_KEY"

# init repo if not exist else run zbackup backup
[ -d "$ZB_REPO" ] || "$ZB_BIN" --password-file "$ZB_KEY" init "$ZB_REPO"

# symlink info
ln -snf "$ZB_INFO" "${ZB_REPO}/"

# rsync index from backup
echo "INFO: sync remote zbackup index..."
rsync -ar -e "ssh -i $SSH_KEY" --rsync-path="sudo rsync" "${SSH_USER}"@"${REMOTE_SERVER}":"${ZB_REPO_REMOTE}/index" "${ZB_REPO}/"

# run backup through zbackup
echo "INFO: creating zbackup backup..."
cat "$ARCHIVE" | "$ZB_BIN" --password-file "$ZB_KEY" backup "${ZB_REPO}/backups/$(basename $ARCHIVE)" &>/dev/null

# rsync backup, bundles, index to backup
echo "INFO: uploading zbackup data"
rsync -ar -e "ssh -i $SSH_KEY" --rsync-path="sudo rsync" "${ZB_REPO}/backups/" "${SSH_USER}"@"${REMOTE_SERVER}":"${ZB_REPO_REMOTE}/backups/${ZB_APP_NAME}/daily"
rsync -ar -e "ssh -i $SSH_KEY" --rsync-path="sudo rsync" "${ZB_REPO}/bundles/" "${SSH_USER}"@"${REMOTE_SERVER}":"${ZB_REPO_REMOTE}/bundles"
rsync -ar -e "ssh -i $SSH_KEY" --rsync-path="sudo rsync" "${ZB_REPO}/index/" "${SSH_USER}"@"${REMOTE_SERVER}":"${ZB_REPO_REMOTE}/index"

# delete backup files, bundles and index 
echo "INFO: cleaning up..."
set -x
rm -f "$ARCHIVE"
rm -rf "${ZB_REPO}/backups/*"
rm -rf "${ZB_REPO}/bundles/*"
rm -rf "${ZB_REPO}/index/*"

# shred keys and backups
shred -u "$ZB_INFO"
shred -u "$ZB_KEY"
set +x
echo "INFO: RD and CA backup successful."