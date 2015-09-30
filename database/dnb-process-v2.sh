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
[ -e /***REMOVED***/scripts/dnb/.dnbftp ] || die "ERROR: dnb ftp credentials file not found"
. /***REMOVED***/scripts/dnb/.dnbftp
###########
#DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Need the same current_files.txt to persist between runs!
DIR=/***REMOVED***/scripts/dnb
DESTINATION="/dnb_files" # Somewhere that's accessible for mysql to load the file
SOURCE="/gets" # on dnb ftp server
CURRENT_FILES="$DIR/current_files.txt"
NEW_FILES="$DIR/new_files.txt"
NEW_FILES_CLEAN="$DIR/new_files_clean.txt"
EXT_DIR=""
TB_STRUCTURES_DIR="$DIR/dnb_table_structures"
## File / DB mappings ##
DB="dnb"
COMPANY_FILE="MonthlyActive.csv"
COMPANY_TABLE="company"
COMPANY_TABLE_COLUMNS="(DunsNumber,Name,TradingStyle,StreetAddress1,StreetAddress2,City,State,Postcode,Country,SicCode,@EmployeesTotal,@AnnualSales,@ImmediateParentDunsNumber,ImmediateParentName,ImmediateParentCountry,GlobalParentDunsNumber,GlobalParentName,GlobalParentCountry,MarketabilityIndicator,LocationIndicator)"
TICKER_FILE="Ticker.csv"
TICKER_TABLE="ticker"
TICKER_TABLE_COLUMNS="(DunsNumber,Ticker,StockExchange,PrimarySE)"
URL_FILE="URLOutput.csv"
URL_TABLE="url"
URL_TABLE_COLUMNS="(DunsNumber,Domain_1,Domain_2,Domain_3,Domain_4,TotalURLs)"
# No columns, the file uses string positioning - https://docs.google.com/a/***REMOVED***.com/spreadsheet/ccc?key=***REMOVED***#gid=0
# Table crafted within the datatype lengths so when load file data gets put in the right place (Brittle)
FIRST_RUN="no"

### Table schema sql ############

# company
cat > "$TB_STRUCTURES_DIR/dnb_company_table_structure.sql" <<"EOF"
USE dnb;
CREATE TABLE IF NOT EXISTS `company_temp` (
  `ID` bigint(11) NOT NULL AUTO_INCREMENT,
  `DunsNumber` bigint(11) ZEROFILL NOT NULL,
  `Name` varchar(255) NOT NULL,
  `TradingStyle` tinytext,
  `StreetAddress1`,
  `StreetAddress2`,
  `City` tinytext,
  `State` tinytext,
  `Postcode` varchar(20),
  `Country` tinytext,
  `SicCode` tinytext,
  `EmployeesTotal` int(11),
  `AnnualSales` bigint(11),
  `ImmediateParentDunsNumber` bigint(11),
  `ImmediateParentName` tinytext,
  `ImmediateParentCountry` tinytext,
  `GlobalParentDunsNumber` tinytext,
  `GlobalParentName` tinytext,
  `GlobalParentCountry` tinytext,
  `MarketabilityIndicator` varchar(50),
  `LocationIndicator` varchar(50),
  `LastUpdateDate` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ID`),
  KEY `duns_number` (`DunsNumber`,`Name`),
  KEY `updated_at` (`LastUpdateDate`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=1152 ROW_FORMAT=COMPRESSED;
EOF

# ticker
cat > "$TB_STRUCTURES_DIR/dnb_ticker_table_structure.sql" <<"EOF"
CREATE TABLE IF NOT EXISTS `ticker_temp` (
  `ID` bigint(11) NOT NULL AUTO_INCREMENT,
  `DunsNumber` bigint(11) ZEROFILL NOT NULL,
  `Ticker` varchar(20) NOT NULL,
  `StockExchange` varchar(100) NOT NULL,
  `PrimarySE` varchar(10),
  `CreationDate` timestamp NULL DEFAULT NULL,
  `LastUpdateDate` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ID`),
  KEY `tickerduns` (`DunsNumber`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ROW_FORMAT=COMPRESSED ;
EOF

# url
cat > "$TB_STRUCTURES_DIR/dnb_url_table_structure.sql" <<"EOF"
CREATE TABLE IF NOT EXISTS `url_temp`(
 `DunsNumber` BIGINT(11) ZEROFILL NOT NULL,
 `Domain_1` VARCHAR(104),
 `Domain_2` VARCHAR(104),
 `Domain_3` VARCHAR(104),                                                                                                
 `Domain_4` VARCHAR(104),
 `TotalURLs` INT(5),
 KEY `urlduns` (`DunsNumber`) 
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ROW_FORMAT=COMPRESSED;
EOF

##################################

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
        echo "${dtable} table creation complete!"
        ;;
      "shuffle")
        echo "${dtable} shuffle start.....!"
        mysql -e "use ${DB}; RENAME TABLE ${dtable} to ${dtable}_del; RENAME TABLE ${dtable}_temp TO ${dtable}; DROP TABLE ${dtable}_del;" || die "ERROR: Failed flipping tables with new data"
        echo "${dtable} shuffle complete!"
        ;;
      "init")
        echo "${dtable} initialise start.....!"
        mysql -e "use ${DB}; RENAME TABLE ${dtable}_temp to ${dtable};" || die "ERROR: Failed initialising new table"
        echo "${dtable} initialise complete!"
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
	   7za e "$i" -o"$EXT_DIR"
    else
      echo "$i is not an archive";
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
        TABLE_NAME="company"
        ;;
      *${URL_FILE}*)
        mv *${URL_FILE}* ${URL_FILE}
        TABLE_NAME="url"
        ;;
      *${TICKER_FILE}*)
        mv *${TICKER_FILE}* ${TICKER_FILE}
        TABLE_NAME="ticker"
        ;;
    esac
    
    TABLE_COLUMNS="${TABLE_NAME^^}_TABLE_COLUMNS"

    table_shuffle "${TABLE_NAME}" create
    echo "Loading in ${TABLE_NAME} table...."
    # Ignore header / 1st line of csv

    [[ "$FIRST_RUN" == "yes" ]] && table_shuffle "${TABLE_NAME}" init

    [[ "$FIRST_RUN" != "yes" ]] && TABLE_NAME="${TABLE_NAME}_temp"

    if [[ "$TABLE_NAME" =~ "$COMPANY_TABLE" ]]; then
      mysql -e "USE $DB; LOAD DATA INFILE '${EXT_DIR}/${dnb_file}' INTO TABLE ${TABLE_NAME} FIELDS TERMINATED BY ',' ENCLOSED BY '\"' ESCAPED BY '' LINES TERMINATED BY '\\r\\n' IGNORE 1 LINES ${!TABLE_COLUMNS} \
      SET AnnualSales = IF(@AnnualSales='',NULL,@AnnualSales), ImmediateParentDunsNumber = IF(@ImmediateParentDunsNumber='',NULL,@ImmediateParentDunsNumber), EmployeesTotal = IF(@EmployeesTotal='',NULL,@EmployeesTotal);" || die "ERROR: Failed to load data into database - ${TABLE_NAME}"
    else
      mysql -e "USE $DB; LOAD DATA INFILE '${EXT_DIR}/${dnb_file}' INTO TABLE ${TABLE_NAME} FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\\r\\n' IGNORE 1 LINES ${!TABLE_COLUMNS};" || die "ERROR: Failed to load data into database - ${TABLE_NAME}"
    fi
    

    [[ "$FIRST_RUN" != "yes" ]] && table_shuffle "${TABLE_NAME}" shuffle

    echo "deleting $dnb_file"
    rm -f "$dnb_file"
  done
}

search_reindex () {
#--after running full index, be sure to stop and start the service again:
#su sphinxsearch -c "/usr/bin/indexer --config /***REMOVED***/var/sphinx.conf --all" # do index
#sudo -u sphinxsearch /usr/bin/searchd --config /***REMOVED***/var/sphinx.conf # start searchd
#/usr/bin/searchd --config /***REMOVED***/var/sphinx.conf --stop # stop searchd

# stop sphinx searchd daemon
#/usr/bin/searchd --config /***REMOVED***/var/sphinx.conf --stop
# remove pid file incase
#rm -rf /***REMOVED***/var/run/sphinxv2.pid

# Ensure we can write new indexes to directory
chown sphinx:sphinx /srv/ssd/sphinx_index -R
chmod 775 /srv/ssd/sphinx_index
find /srv/ssd/sphinx_index -type f -exec chmod 664 {} \;

# Create new indexes
#su sphinxsearch -c "/usr/bin/indexer --config /***REMOVED***/var/sphinx.conf --all" || die "ERROR: Sphinx search re-index failed."
sudo -u sphinx /usr/bin/indexer --config /etc/sphinx/sphinx.conf --rotate --all || die "ERROR: Sphinx search re-index failed."
#sudo -u sphinxsearch /usr/bin/searchd --config /***REMOVED***/var/sphinx.conf || die "ERROR: Sphinx searchd daemon failed to start."

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
