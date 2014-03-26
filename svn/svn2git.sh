#!/bin/bash -x

DIR=$(cd "$(dirname "$0")" && pwd)
die() { echo $* 1>&2 ; exit 1 ; }

# Settings
SVNPROJECTSBASE="https://***REMOVED***.***REMOVED***.com/svn/trunk/projects"
AUTHORS_FILE="--authors-file=${DIR}/authors.txt"
CLONE_OPTIONS="--no-metadata --prefix=svn/"
PROJECTS="restserver social zaibatsu"
CORE_PROJECTS="common intranet website"
WORKDIR="$DIR/svnwork"
# Validate
which svn 2>&1 > /dev/null || die "ERROR: svn application not installed"
which git 2>&1 > /dev/null || die "ERROR: svn application not installed"
[ -d "${WORKDIR}" ] || mkdir "${WORKDIR}"

cd "${WORKDIR}"

# Clone projects from SVN as git repositories as their own folder.
for project in $PROJECTS; do
  #echo $project
  git svn clone ${SVNPROJECTSBASE}/${project} ${AUTHORS_FILE} ${CLONE_OPTIONS} ${project} || die "ERROR: can not clone from svn repo - ${project}"
  cd ${project}
  git svn-abandon-fix-refs
  git branch -m git-svn master
  git svn-abandon-cleanup
  git config --remove-section svn
  git config --remove-section svn-remote.svn
  rm -rf .git/svn .git/{logs/,}refs/remotes/{git-,}svn/
  git remote add origin git@***REMOVED***.***REMOVED***.com:***REMOVED***/${project}.git
  git push -u origin master
  cd -
done

for project in $CORE_PROJECTS; do
  #echo $project
  git svn clone ${SVNPROJECTSBASE}/${project} ${AUTHORS_FILE} ${CLONE_OPTIONS} ${project} || die "ERROR: can not clone from svn repo - ${project}"
  cd ${project}
  git svn-abandon-fix-refs # pauses on weird error, run on older version of git
  git branch -m git-svn master
  git svn-abandon-cleanup
  git config --remove-section svn
  git config --remove-section svn-remote.svn
  rm -rf .git/svn .git/{logs/,}refs/remotes/{git-,}svn/
  #git remote add origin git@***REMOVED***.***REMOVED***.com:***REMOVED***/core.git
  #git push -u origin master
  cd -
done

make_core () {
  # COMBINE REPO's
  cd ${WORKDIR}
  mkdir core
  cd core
  git init
  touch delme.txt
  git add .
  git commit -m "Initial dummy commit"
  for i in intranet website core; do 
	git remote add -f local_$i file://${WORKDIR}/$i
	git merge local_$i/master -m "Merging $i into core" 
	mkdir $i
	#git mv * $i # change as doesn't work
	for proj_file in `ls -A`; do [[ "$proj_file" != "$i" ]] && [[ "$proj_file" != .git ]] && git mv $proj_file $i; done
	git commit -m "Move $i files into subdir"
  done
  git rm delme.txt
  git commit -m "Clean up dummy file"
  git remote add origin git@***REMOVED***.***REMOVED***.com:***REMOVED***/core.git
  git push -u origin master
}

make_core

# cleanup
# remove core or entire workdir