#!/bin/bash

APP_ENV="@option.environment@"
die() { echo $* 1>&2 ; exit 1 ; }

REPO_UPDATE_SCRIPT="/cognolink/bin/update_rep_poc"

[ -e "$REPO_UPDATE_SCRIPT" ] || die "ERROR: repo update script not found - $REPO_UPDATE_SCRIPT"

[ -z "$APP_ENV" ] && die "ERROR: no application environment value (e.g. dev, uat, qa, prod)"

"$REPO_UPDATE_SCRIPT" "$APP_ENV" || die "ERROR: repository update / rebuild failed"

exit 0