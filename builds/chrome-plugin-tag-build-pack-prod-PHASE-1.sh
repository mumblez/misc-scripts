#!/bin/bash -e
#
# Purpose: Pack a Chromium extension directory into crx format
# Will do so per branch

die() { echo $* 1>&2 ; exit 1 ; }

### Prerequisites ###
# mkdir /srv/chrome-plugin-build
# mkdir /srv/chrome-plugin

### Settings ###
TIMESTAMP=$(date +%Y-%m-%d-%H%M)
#PLUGIN=""   # provide via rundeck
PLUGIN="@option.plugin@"   # git repo / project
TAG="@option.tag@"
REPO_URL="@option.repo_url@"
#REPO_KEY="/root/keys/cl_deploy" # for rundeck
BUILD_ROOT="/srv/chrome-plugin-build"
REPO_KEY="/root/keys/cl_deploy" # for debug
KEY_NAME="${PLUGIN}.pem"
WEB_ROOT="/srv/chrome-plugin/${PLUGIN}/release/${TIMESTAMP}"
WEB_HOST_URL="http://some.plugin.url"
mkdir -p "${WEB_ROOT}"
PHASE="@option.phase@" # we'll keep original urls in manifest and xml and create symlinks
#PHASE=2 # When Matt / Kris have created sub groups / organisations in google apps console and we can deploy via new url,
###   the urls will need to be updated with the new domain (WEB_HOST_URL) before switching to this phase

### chrome packing settings
dir="${BUILD_ROOT}/${PLUGIN}/${PLUGIN}"
key="${BUILD_ROOT}/${PLUGIN}/${KEY_NAME}"
name="$PLUGIN"
crx="$name.crx"
pub="$name.pub"
sig="$name.sig"
zip="$name.zip"

trap 'rm -rf "$pub" "$sig" "$zip" "${BUILD_ROOT}/${PLUGIN}"' EXIT

TOOLS="zip openssl printf awk git xxd ssh-agent ssh-add sha256sum"

### Validation ####
# check all tools exist
for TOOL in $TOOLS; do
	which $TOOL &>/dev/null || die "ERROR: $TOOL is not installed"
done

# check files / directories exist
for FILE in $REPO_KEY $BUILD_ROOT; do
	[ -e $FILE ] || die "ERROR: file or directory $FILE does not exist"
done



### Pull down repo in $BUILD_ROOT - pull fresh each time

ssh-agent bash -c "ssh-add $REPO_KEY &>/dev/null && git clone $REPO_URL ${BUILD_ROOT}/${PLUGIN}" ||\
	die "ERROR: Git clone from $REPO_URL failed"
# assumes if repo branch folder doesn't exist it's branch in webroot also doesn't exist
[ ! -e "$WEB_ROOT" ] && mkdir -p "$WEB_ROOT"



cd "${BUILD_ROOT}/${PLUGIN}"
git checkout "$TAG" &>/dev/null || die "ERROR: Failed to checkout $TAG"


# chrome package process - create crx

cd "${BUILD_ROOT}/${PLUGIN}"

# zip up the crx dir
cwd=$(pwd -P)
(cd "$dir" && zip -qr -9 -X "$cwd/$zip" .)

# signature
openssl sha1 -sha1 -binary -sign "$key" < "$zip" > "$sig"

# public key
openssl rsa -pubout -outform DER < "$key" > "$pub" 2>/dev/null

byte_swap () {
  # Take "abcdefgh" and return it as "ghefcdab"
  echo "${1:6:2}${1:4:2}${1:2:2}${1:0:2}"
}

crmagic_hex="4372 3234" # Cr24
version_hex="0200 0000" # 2
pub_len_hex=$(byte_swap $(printf '%08x\n' $(ls -l "$pub" | awk '{print $5}')))
sig_len_hex=$(byte_swap $(printf '%08x\n' $(ls -l "$sig" | awk '{print $5}')))
(
  echo "$crmagic_hex $version_hex $pub_len_hex $sig_len_hex" | xxd -r -p
  cat "$pub" "$sig" "$zip"
) > "$crx"

# Move crx to new location (nfs share )
mv "${PLUGIN}.crx" "$WEB_ROOT" || die "ERROR: Failed to transfer crx to webserver"
mv "${PLUGIN}.xml" "$WEB_ROOT" || die "ERROR: Failed to transfer xml to webserver"

# Symlink both files to webroot
ln -snf "${WEB_ROOT}/${PLUGIN}.crx" "${WEB_ROOT}/../../"
ln -snf "${WEB_ROOT}/${PLUGIN}.xml" "${WEB_ROOT}/../../"

# Symlink from intranet.cognolink.com/chrome-plugin/<plugin>.{xml,crx} (until users have been re-organised in google apps console)
if [ "$PHASE" = "1" ]; then
	# create symlinks to original domain
	OLD_CRX_WEB_ROOT="/cognolink/www/intranet/chrome-plugin"

	# random names!!!
	OLD_CAPTURE_SPECIALIST_CRX="${OLD_CRX_WEB_ROOT}/capture-specialist.crx"
	OLD_CAPTURE_SPECIALIST_XML="${OLD_CRX_WEB_ROOT}/specialist-updates.xml"
	OLD_GMAIL_INTRANET_LINK_CRX="${OLD_CRX_WEB_ROOT}/Gmail-Intranet Link.crx"
	OLD_GMAIL_INTRANET_LINK_XML="${OLD_CRX_WEB_ROOT}/gmail-intranet-link.xml"
	OLD_CAPTURE_PROSPECTS_CRX="${OLD_CRX_WEB_ROOT}/capture.crx"
	OLD_CAPTURE_PROSPECTS_XML="${OLD_CRX_WEB_ROOT}/updates.xml"
	OLD_GMAIL_NEW_PROJECT_REQUEST_CRX="${OLD_CRX_WEB_ROOT}/gmail-new-project-request.crx"
	OLD_GMAIL_NEW_PROJECT_REQUEST_XML="${OLD_CRX_WEB_ROOT}/gmail-new-project-request.xml"

	case $PLUGIN in
		capture-specialist )
			ln -snf "${WEB_ROOT}/${PLUGIN}.crx" "$OLD_CAPTURE_SPECIALIST_CRX"
			ln -snf "${WEB_ROOT}/${PLUGIN}.xml" "$OLD_CAPTURE_SPECIALIST_XML"
			;;
		capture-prospects )
			ln -snf "${WEB_ROOT}/${PLUGIN}.crx" "$OLD_CAPTURE_PROSPECTS_CRX"
			ln -snf "${WEB_ROOT}/${PLUGIN}.xml" "$OLD_CAPTURE_PROSPECTS_XML"
			;;
		gmail-intranet-link )
			ln -snf "${WEB_ROOT}/${PLUGIN}.crx" "$OLD_GMAIL_INTRANET_LINK_CRX"
			ln -snf "${WEB_ROOT}/${PLUGIN}.xml" "$OLD_GMAIL_INTRANET_LINK_XML"
			;;
		gmail-new-project-request )
			ln -snf "${WEB_ROOT}/${PLUGIN}.crx" "$OLD_GMAIL_NEW_PROJECT_REQUEST_CRX"
			ln -snf "${WEB_ROOT}/${PLUGIN}.xml" "$OLD_GMAIL_NEW_PROJECT_REQUEST_XML"
			;;
		* )
			ln -snf "${WEB_ROOT}/${PLUGIN}.crx" "${OLD_CRX_WEB_ROOT}/"
			ln -snf "${WEB_ROOT}/${PLUGIN}.xml" "${OLD_CRX_WEB_ROOT}/"
			;;
	esac
	echo "INFO: symlinks to intranet.cognolink.com/chrome-plugin created (PHASE 1)"
	chown www-data:www-data "$OLD_CRX_WEB_ROOT" -R
fi

chown www-data:www-data /srv/chrome-plugin -R
EID=$(cat $key | openssl rsa -pubout -outform DER 2>/dev/null | sha256sum | cut -c 1-32 | tr '0-9a-f' 'a-p')

echo "INFO: plugin built and deployed."
echo "=================================================================================================="
echo "INFO: Symlinks from old urls are pointing to the latest release"
echo "INFO: Extension ID: $EID"
echo "=================================================================================================="

# CLEANUP
echo "INFO: Cleaning up..."
# Clearing old releases
CURRENT_RELEASE=$(basename $(readlink "/srv/chrome-plugin/${PLUGIN}/${PLUGIN}.crx"))
RECENT_RELEASES=$(ls -tr1 "/srv/chrome-plugin/${PLUGIN}/release" | grep -v "$CURRENT_RELEASE" | tail -n4)
for OLD_RELEASE in $(ls -tr1 "/srv/chrome-plugin/${PLUGIN}/release" | grep -v "$CURRENT_RELEASE"); do
	if ! echo "$OLD_RELEASE" | grep -q "$RECENT_RELEASES"; then
		echo "INFO: Deleted old release - $OLD_RELEASE"
		rm -rf "/srv/chrome-plugin/${PLUGIN}/release/${OLD_RELEASE}"
	fi
done
