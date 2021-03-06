#!/bin/bash -x

DIR=$(cd "$(dirname "$0")" && pwd)
die() { echo $* 1>&2 ; exit 1 ; }

# Settings
SVNPROJECTSBASE="https://somesvnserver/svn/trunk/projects"
AUTHORS_FILE="--authors-file=${DIR}/authors.txt"
CLONE_OPTIONS="--no-metadata --prefix=svn/ --preserve-empty-dirs"
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
  # check and add ignored files ######
  ####################################
  git svn-abandon-fix-refs
  git branch -m git-svn master
  git svn-abandon-cleanup
  git config --remove-section svn
  git config --remove-section svn-remote.svn
  rm -rf .git/svn .git/{logs/,}refs/remotes/{git-,}svn/
  git remote add origin git@somegitserver:somecomp/${project}.git
  git push --force -u origin master
  cd -
done

for project in $CORE_PROJECTS; do
  #echo $project
  git svn clone ${SVNPROJECTSBASE}/${project} ${AUTHORS_FILE} ${CLONE_OPTIONS} ${project} || die "ERROR: can not clone from svn repo - ${project}"
  cd ${project}
  # check and add ignored files ######
  ####################################
  git svn-abandon-fix-refs # pauses on weird error, run on older version of git
  git branch -m git-svn master
  git svn-abandon-cleanup
  git config --remove-section svn
  git config --remove-section svn-remote.svn
  rm -rf .git/svn .git/{logs/,}refs/remotes/{git-,}svn/
  #git remote add origin git@somegitserver:somecomp/core.git
  #git push --force -u origin master
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
  for i in intranet website common; do
    #cd ${WORKDIR}/core
  	git remote add -f local_$i file://${WORKDIR}/$i
  	git merge local_$i/master -m "Merging $i into core"
  	mkdir $i
    #git mv * $i # change as doesn't work
    #for proj_file in `ls -A`; do [[ "$proj_file" != "$i" && "$proj_file" != .git ]] && git mv $proj_file $i; done
    for proj_file in `ls -A`; do
      if [[ "$proj_file" != "delme.txt" || "$proj_file" != "intranet" && "$proj_file" != "website" && "$proj_file" != "common" && "$proj_file" != ".git" ]]; then
        git mv $proj_file $i
      fi
    done
    git commit -m "Move $i files into subdir"
  done
  git rm delme.txt
  git commit -m "Clean up dummy file"
  #git reset --soft HEAD~7
  #git commit -m "svn 2 git"
  git remote add origin git@somegitserver:somecomp/core.git
  git push --force -u origin master
}

make_core

# cleanup
# remove core or entire workdir
rm -rf "${WORKDIR}"
