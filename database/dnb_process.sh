#!/bin/bash
#
# Script to pull latest DNB files and upload into DB
# Author: Yusuf Tran
# Date: 12/11/2013
#
#
# Changes:
# 19/11/2013
# - Tweaked to use lftp one liners, will simply list and compare directories vs md5sum after download, this will be alot more efficient
# 02/01/2014
# - Correct display / echo statements to show new found files
# 03/01/2014
# - Added 'company' restore procedure (still awaiting ticker and url file)
# 09/01/2014
# - Added 'url' and 'company' procedures, URL file format uses positions within the string to seperate
# values, to make this work had to use latin1 character set vs utf8, hopefully this won't bite us
# 17/03/2014
# Make more compatible with rundeck, purposely die on error so can trigger correct alerts / workflow
# 06/05/2014
# Updated with new server in France - OVH
# 21/05/2014
# Use 7z (p7zip) instead, normal unzip is unable to decompress sometimes complaining zip is corrupt
# 25/09/2015
# Amend to use new naming format and format of data

# TO DO, build in alot more validation checks

### Settings ###
die() { echo $* 1>&2 ; exit 1 ; }
################
# DNB FTP #
[ -e /root/scripts/dnb/.dnbftp ] || die "ERROR: dnb ftp credentials file not found"
. /root/scripts/dnb/.dnbftp
###########
#DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Need the same current_files.txt to persist between runs!
DIR=/root/scripts/dnb
DESTINATION="/dnb_files" # Somewhere that's accessible for mysql to load the file
SOURCE="/gets" # on dnb ftp server
CURRENT_FILES="$DIR/current_files.txt"
NEW_FILES="$DIR/new_files.txt"
NEW_FILES_CLEAN="$DIR/new_files_clean.txt"
EXT_DIR=""
TB_STRUCTURES_DIR="$DIR/dnb_table_structures"
## File / DB mappings ##
DB="dnb"
COMPANY_FILE="some.csv"
COMPANY_TABLE="company"
COMPANY_TABLE_COLUMNS="(DunsNumber,Name,TradingStyle,StreetAddress1,StreetAddress2,City,State,Postcode,Country,SicCode,EmployeesTotal,AnnualSales,ImmediateParentDunsNumber,ImmediateParentName,ImmediateParentCountry,GlobalParentDunsNumber,GlobalParentName,GlobalParentCountry,MarketabilityIndicator,LocationIndicator)"
TICKER_FILE="some_TickerFile.csv"
TICKER_TABLE="ticker"
TICKER_TABLE_COLUMNS="(SourceID,Ticker,StockExchange)"
URL_FILE="URLFile.txt"
URL_TABLE="url"
# No columns, the file uses string positioning - https://docs.google.com/a/some.com/spreadsheet/ccc?key=0Ag6KaevjpAvMdFhyUUFjNTFXczBEMHJ3TzY5VDdBemc#gid=0
# Table crafted within the datatype lengths so when load file data gets put in the right place (Brittle)

### Settings End ###
####################

### Validation ###
[ -e /etc/sphinx/sphinx.conf ] || die "ERROR: sphinx.conf not found"
[ -e /usr/bin/indexer ] || die "ERROR: sphinx indexer not found on system"
[ -e "$CURRENT_FILES" ] || die "ERROR: current_files.txt not found"
[ -d "$TB_STRUCTURES_DIR" ] || die "ERROR: table structure folder not found"
which 7za || die "ERROR: 7za not found"

### Functions ###
table_shuffle () {
    dtable="$1"
    doption="$2"

    case $doption in
      "create")
        # Load into temporary table, rename old one, rename new one, drop old one!
        # #file pattern dnb_<table>_table_structure.sql
        # table structure files have table names with "_temp" suffix, e.g. url_temp
        mysql < "$TB_STRUCTURES_DIR/dnb_${dtable}_table_structure.sql" || die "ERROR: Failed importing dnb_${dtable}_table_structure.sql"
        echo "${dtable}_temp table creation complete!"
        ;;
      "shuffle")
            echo "${dtable} shuffle start.....!"
        mysql -e "use ${DB}; RENAME TABLE ${dtable} to ${dtable}_del; RENAME TABLE ${dtable}_temp TO ${dtable}; DROP TABLE ${dtable}_del;" || die "ERROR: Failed flipping tables with new data"
        echo "${dtable} shuffle complete!"
        ;;
    esac
}

check_new_files () {
    # Get file listing, compare against current and save newly detected files
    echo "Checking files..."
    lftp -e "ls ${SOURCE}; exit" -u ${USER},${PASS} ${HOST} | grep -vE "^total " | grep -vf "$CURRENT_FILES" > "$NEW_FILES"
}

extract_new_files () {
  EXT_DIR=$(mktemp -d "$DESTINATION"/extracted.XXXXXX)
  ### Loop through new files, detect extension and extract accordingly
  cd "$DESTINATION/$SOURCE"
  echo "current directory: `pwd`"
  echo "current files to extract...."
  echo "$(ls)"
  while read i; do
    EXTENSION=$(echo $i | rev | cut -d'.' -f 1 | rev)
    if [ "$EXTENSION" = "zip" ]; then
      echo "unzipping $i"
      #unzip "$i" -d "$EXT_DIR" || die "ERROR: Failed to unzip $i"
	  # 7za e some_20_May_2014.zip [-o<output dir>]
      #unzip "$i" -d "$EXT_DIR" || die "ERROR: Failed to unzip $i"
	  7za e "$i" -o"$EXT_DIR"
    elif [ "$EXTENSION" = "rar" ]; then
      echo "unraring $i" || die "ERROR: Failed to unrar $i"
      unrar x "$i" "$EXT_DIR";
    else
      echo "$i is not an archive";
      if [[ "$EXTENSION" == "csv" ]] && [[ "$i" == "$TICKER_FILE" || "$i" == *icker* ]]; then
        ln -s "${DESTINATION}${SOURCE}/$i" "${EXT_DIR}/${TICKER_FILE}"
            echo "symlinked TickerFile to $EXT_DIR/$TICKER_FILE"
      fi
    fi;
  done < "$NEW_FILES_CLEAN"
  chmod +rx "$EXT_DIR" -R
  ls -ld "$EXT_DIR"
  ls -l "$EXT_DIR"
}

db_loadup () {
  ### Upload to databases
  ## File names for url and ticket files may possibly be the same each period,
  ## relying on the fact that they remove the files, we will use this to detect changes
  cd "$EXT_DIR"
  for dnb_file in $(ls); do
    ### code to import csv / txt files into existing dbs or drop and recreate, confirm with Gyula ###
    case "$dnb_file" in
      *${COMPANY_FILE}*)
        # add logic to rename file name
        mv *${COMPANY_FILE}* ${COMPANY_FILE}
        table_shuffle "${COMPANY_TABLE}" create
        echo "Loading in 'company' table...."
        # Ignore header / 1st line of csv
        mysql -e "USE $DB; LOAD DATA INFILE '${EXT_DIR}/${COMPANY_FILE}' INTO TABLE ${COMPANY_TABLE}_temp FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\\r\\n' IGNORE 1 LINES ${COMPANY_TABLE_COLUMNS};" || die "ERROR: Failed to load data into database - ${COMPANY_TABLE}"
        table_shuffle "${COMPANY_TABLE}" shuffle
        ;;
      *{$URL_FILE}*)
        mv *{$URL_FILE}* {$URL_FILE}
        table_shuffle "${URL_TABLE}" create
        echo "Loading in 'url' table..."
        mysql -e "USE $DB; LOAD DATA INFILE '${EXT_DIR}/${URL_FILE}' INTO TABLE ${URL_TABLE}_temp FIELDS TERMINATED BY '' LINES TERMINATED BY '\\r\\n';" || die "ERROR: Failed to load data into database - ${URL_TABLE}"
        # Clean up whitespace for domain names
        for i in $(seq 1 5); do
          mysql -e "UPDATE ${DB}.${URL_TABLE}_temp SET domain_${i} = RTRIM(domain_${i});" || die "ERROR: Failed to clean up whitespace for domains"
        done
        table_shuffle "${URL_TABLE}" shuffle
        ;;
      *${TICKER_FILE}*)
        mv *${TICKER_FILE}* ${TICKER_FILE}
        table_shuffle "${TICKER_TABLE}" create
        echo "Loading in 'ticker' table..."
        mysql -e "USE $DB; LOAD DATA INFILE '${EXT_DIR}/${TICKER_FILE}' INTO TABLE ${TICKER_TABLE}_temp FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\\r\\n' IGNORE 1 LINES ${TICKER_TABLE_COLUMNS};" || die "ERROR: Failed to load data into database - ${URL_TABLE}"
        table_shuffle "${TICKER_TABLE}" shuffle
        ;;
    esac
        echo "deleting $dnb_file"
    rm -f "$dnb_file"
  done
}

search_reindex () {
#--after running full index, be sure to stop and start the service again:
#su sphinxsearch -c "/usr/bin/indexer --config /some/var/sphinx.conf --all" # do index
#sudo -u sphinxsearch /usr/bin/searchd --config /some/var/sphinx.conf # start searchd
#/usr/bin/searchd --config /some/var/sphinx.conf --stop # stop searchd

# stop sphinx searchd daemon
#/usr/bin/searchd --config /some/var/sphinx.conf --stop
# remove pid file incase
#rm -rf /some/var/run/sphinxv2.pid

# Ensure we can write new indexes to directory
chown sphinx:sphinx /srv/ssd/sphinx_index -R
chmod 775 /srv/ssd/sphinx_index
find /srv/ssd/sphinx_index -type f -exec chmod 664 {} \;

# Create new indexes
#su sphinxsearch -c "/usr/bin/indexer --config /some/var/sphinx.conf --all" || die "ERROR: Sphinx search re-index failed."
sudo -u sphinx /usr/bin/indexer --config /etc/sphinx/sphinx.conf --rotate --all || die "ERROR: Sphinx search re-index failed."
#sudo -u sphinxsearch /usr/bin/searchd --config /some/var/sphinx.conf || die "ERROR: Sphinx searchd daemon failed to start."

}

### End Functions ####

## MAIN ##

check_new_files

# If new files exist
if [ -s $NEW_FILES ]; then
  echo "New files detected!"
  echo "Files:"
  echo "$(cat $NEW_FILES)"
  echo "Downloading new files...."
  cd "$DESTINATION"
  lftp -e "mirror --delete --only-newer ${SOURCE}; exit" -u ${USER},${PASS} ${HOST} || die "ERROR: Failed to mirror / download files from dnb ftp!"

  echo "Clean up listing of new files"
  cat "$NEW_FILES" | rev | cut -d' ' -f 1 | rev > "$NEW_FILES_CLEAN"
  # Relying on files with same name (URL and Ticker) to be removed so when a new one is uploaded
  # we notice that it's new, else complicated hashing and storage of past hashes / files must be
  # performed.

  extract_new_files
  db_loadup

  # Clean up files
  echo "Deleting $NEW_FILES"
  rm -f "$NEW_FILES"
  echo "Deleting $NEW_FILES_CLEAN"
  rm -f "$NEW_FILES_CLEAN"
  echo "Deleting $EXT_DIR"
  rm -rf "$EXT_DIR"

  # Create a full sphinx search re-index
  search_reindex

else
  echo "No new files"
fi

# UPDATE current_files.txt
ls "${DESTINATION}${SOURCE}" > "${CURRENT_FILES}"

exit 0
