#!/bin/bash



for link in $(find /somecomp -type l); do
  ORIGINALLINK=$(readlink $link)
  NEWLINK=$(echo $ORIGINALLINK | sed 's/olduser/newuser/g')
#  echo "File: $link"
#  echo "Original Link: $ORIGINALLINK"
#  echo "New link: $NEWLINK"
  ln -sf $NEWLINK $link
done

# do the same for ~/dev (of new user)
