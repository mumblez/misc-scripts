#!/bin/bash
#
# Script to pull latest DNB files and upload into DB
# Author: Yusuf Tran
# Date: 12/11/2013
#
# Changes:
# 19/11/2013
# - Tweaked to use lftp one liners, will simply list and compare directories vs md5sum after download, this will be alot more efficient 
# 02/01/2014
# - Correct display / echo statements to show new found files

### Settings ###
HOST="ftp.dnb.com"
USER="cognolnk"
PASS="mpzhct36"
DESTINATION="/***REMOVED***/dnb_files"
SOURCE="/gets"
CURRENT_FILES="/***REMOVED***/scripts/current_files.txt"
NEW_FILES="/***REMOVED***/scripts/new_files.txt"
NEW_FILES_CLEAN="/***REMOVED***/scripts/new_files_clean.txt"
### Settings End ###


# Get file listing, compare against current and save newly detected files
echo "Checking files..."
lftp -e "ls ${SOURCE}; exit" -u ${USER},${PASS} ${HOST} | grep -vE "^total " | grep -vf $CURRENT_FILES > $NEW_FILES

# If new files exist
if [ -s $NEW_FILES ]; then
  echo "New files detected!"
  echo "Files: `cat $NEW_FILES`"
  echo "Downloading new files...."
  cd $DESTINATION
  lftp -e "mirror --delete --only-newer ${SOURCE}; exit" -u ${USER},${PASS} ${HOST}

  echo "Clean up listing of new files"
  cat $NEW_FILES | rev | cut -d' ' -f 1 | rev > $NEW_FILES_CLEAN

  #cd ${DESTINATION}${SOURCE}
  EXT_DIR=$DESTINATION/$(mktemp -d extracted.XXXXXX)/
  # code to loop through new files, detect extension and extract accordingly
  while read i; do
    EXTENSION=$(echo $i | rev | cut -d'.' -f 1 | rev)
    if [ "$EXTENSION" = "zip" ]; then
      echo "unzipping $i"
      unzip "$i" -d "$EXT_DIR";
    elif [ "$EXTENSION" = "rar" ]; then
      echo "unraring $i"
      unrar x "$i" "$EXT_DIR";
    else
      echo "$i is not an archive";
    fi;
  done < $NEW_FILES_CLEAN

  ### Upload to databases  ####  UNDER CONSTRUCTIONS #####
  cd $EXT_DIR
  for i in `ls`; do
    ### code to import csv / txt files into existing dbs or drop and recreate, confirm with Gyula ###
    echo "Importing $i to db... (under construction)";
  done

  # Clean up files
  rm -rf /***REMOVED***/scripts/new_files*
  #rm -rf $EXT_DIR

  # UPDATE current_files.txt

else
  echo "No new files";
fi
