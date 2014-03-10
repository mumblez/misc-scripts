#/bin/bash
# bzip2 compress a folder (multi-threaded with pbzip2)

# SETTINGS #
FILE_DATE=$(date +%Y-%m-%d)
FILE_NAME=@option.file_name@
COMPRESSED_FILE="$FILE_DATE-$FILE_NAME.bz2"
SOURCE_DIR=@option.source_dir@
DESTINATION_DIR=@option.destination_dir@
DIR=$(cd "$(dirname "$0")" && pwd)

# FUNTIONS
die() { echo $* 1>&2 ; exit 1 ; }

# VALIDATION #
which pbzip2 > /dev/null || die "ERROR: pbzip2 not installed!"
[ -d "$SOURCE_DIR" ] || die "ERROR: $SOURCE_DIR not found"
[ -d "$DESTINATION_DIR" ] || die "ERROR: $DESTINATION_DIR not found"

# MAIN #
echo "$SOURCE_DIR size:"
df -h
echo "Compressing $SOURCE_DIR"
tar -cf "$DESTINATION_DIR/$COMPRESSED_FILE" -C "$SOURCE_DIR" . --use-compress-prog=pbzip2 || die "ERROR: unable to compress $SOURCE_DIR"
ls -lh "$DESTINATION_DIR"

# FINISH #
exit 0
