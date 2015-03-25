#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)

# create the first backup and checkpoint directory
innobackupex --no-timestamp --extra-lsndir ${DIR}/last-checkpoint ${DIR}/hotcopy

# apply log ready for incrementals
innobackupex --apply-log --redo-only ${DIR}/hotcopy

# create incrementals base dir
mkdir ${DIR}/incrementals

# symlink to /var/log
ln -snf /var/log/innobackupex logs

# create realised directory
cp -ar ${DIR}/hotcopy ${DIR}/realised

