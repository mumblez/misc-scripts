#!/bin/bash



for link in $(find /***REMOVED*** -type l); do
  ORIGINALLINK=$(readlink $link)
  NEWLINK=$(echo $ORIGINALLINK | sed 's/***REMOVED***/***REMOVED***/g')
#  echo "File: $link"
#  echo "Original Link: $ORIGINALLINK"
#  echo "New link: $NEWLINK"
  ln -sf $NEWLINK $link
done

# do the same for ~/dev (of new user)