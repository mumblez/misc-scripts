#!/usr/bin/env bash

# conda borks - CONDA_PATH_BACKUP: unbound variable
# set -euo pipefail

die() {
    echo "$*" 1>&2
    exit 1
}

[ $# -lt 3 ] && die "Not enough arguments supplied"

## Settings ##
WORKDIR="$(mktemp -d /tmp/rdjob-XXXXX)"
[ $? != 0 ] && exit 1

PYTHON_VERSION="$1"
JOB_DIR="${RD_GLOBALS_SCM_ROOT}/${2}"
JOB_SCRIPT="$3"
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

JOB_NAME=$(echo "$RD_JOB_NAME" | tr ' ' '_' | tr -cd '[[:alnum:]]._-')
CUSTOM_ENV="${JOB_NAME}"

## Cleanup environment and files on exit ##
cleanup() {
    cd "$DIR"
    [ -d "$WORKDIR" ] && rm -rf "$WORKDIR"
    conda deactivate || true
}
trap cleanup EXIT SIGINT SIGQUIT SIGKILL SIGHUP SIGTERM

# Copy job files
cd "$WORKDIR"
cp -rf "${JOB_DIR}/." .

## Generate creds and files (unique to each job!)
make rundeck-genenv || die "Failed to generate environment variables for job"

## if job.env doesn't exist just create dummy file
[ -e job.env ] || touch job.env

if ! conda env list | grep -qw $CUSTOM_ENV; then
    conda create -q -y -n $CUSTOM_ENV python=$PYTHON_VERSION
    echo "New conda environment created for $CUSTOM_ENV"
else
    echo "Re-using existing conda env for $CUSTOM_ENV"
fi

source /usr/local/miniconda3/etc/profile.d/conda.sh || die "Error: Failed to source conda config"

conda activate $CUSTOM_ENV || die "Failed to activate conda env: $CUSTOM_ENV"
pip install -r requirements.txt
export $(cat job.env | xargs) && python "$JOB_SCRIPT" || die "Error, job failed!"
echo "Job successfully completed"

