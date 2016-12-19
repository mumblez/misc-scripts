#!/bin/bash


PROJECT="@option.repository@"
PROJECT_SYMFONY_ROOT="/somecomp/lib/php5/$PROJECT"
PROJECT_FPM_CONF="/etc/php5/fpm/pool.d/${PROJECT}.conf"

die() { echo $* 1>&2 ; exit 1 ; }

### Validation checks ###
[ -d "$PROJECT_SYMFONY_ROOT" ] || die "ERROR: $PROJECT_SYMFONY_ROOT symfony root not found"

### externalapi project ###
p_externalapi () {
  KEYS_PATH="/root/keys"
  GCAL_PATH="/root/web"
  GCAL_KEY="somekey"

  # Validation Checks
  if [ -e "${GCAL_PATH}/${GCAL_KEY}" ]; then
    echo "INFO: intranet-calendar key found"
    ln -snf "${GCAL_PATH}/${GCAL_KEY}" "$PROJECT_SYMFONY_ROOT/" && echo "INFO: Added google calendar api key (symlinked)" || die "ERROR: Failed to added google calendar api key"
  elif [ -e "${KEYS_PATH}/${GCAL_KEY}" ]; then
    mkdir -p "$GCAL_PATH"
    cp "${KEYS_PATH}/${GCAL_KEY}" "$GCAL_PATH"
  fi

  # Find user and group perms of project and set permissions on key
  P_USER=$(awk '/^user = .*/ {print $3}' $PROJECT_FPM_CONF)
  P_GROUP=$(awk '/^group = .*/ {print $3}' $PROJECT_FPM_CONF)
  chown ${P_USER}:${P_GROUP} "${GCAL_PATH}" -R
}

case $PROJECT in
	externalapi)
	    p_externalapi
		;;
	*)
	    # Nothing to do
	    exit 0
	    ;;
esac

echo "INFO: Post deployment steps for - $PROJECT - complete"

exit 0
