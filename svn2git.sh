#!/bin/bash -x

SVNPROJECTSBASE="https://***REMOVED***.***REMOVED***.com/svn/trunk/projects"
AUTHORS_FILE="--authors-file=/home/***REMOVED***/.svn2git/authors"
CLONE_OPTIONS="--no-metadata --prefix=svn/"
#PROJECTS="restserver social trackers zaibatsu website-2.0 website"
#PROJECTS="website-2.0"
#PROJECTS="common intranet Symfony"
PROJECTS="symfony"


# Clone projects from SVN as git repositories as their own folder.
for project in $PROJECTS; do
  #echo $project
  git svn clone ${SVNPROJECTSBASE}/${project} ${AUTHORS_FILE} ${CLONE_OPTIONS} ${project} 
  cd ${project}
  git svn-abandon-fix-refs
  git branch -m git-svn master
  git svn-abandon-cleanup
  git config --remove-section svn
  git config --remove-section svn-remote.svn
  rm -rf .git/svn .git/{logs/,}refs/remotes/{git-,}svn/
  git remote add origin git@gitlab.poc.***REMOVED***.com:***REMOVED***_app/${project}.git
  git push -u origin master
  cd -
done