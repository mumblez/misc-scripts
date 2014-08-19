#!/bin/bash -e
#
# Purpose: Pack a Chromium extension directory into crx format
# Will do so per branch

die() { echo $* 1>&2 ; exit 1 ; }
### Settings ###
#PLUGIN=""   # provide via rundeck
PLUGIN="capture-specialist"   # git repo / project
TAG="***REMOVED***"
REPO_URL="git@***REMOVED***.***REMOVED***.com:chrome-plugins/${PLUGIN}.git"
#REPO_KEY="/***REMOVED***/keys/cl_deploy" # for rundeck
BUILD_ROOT="/srv/chrome-plugin-build"
REPO_KEY="${BUILD_ROOT}/cl_deploy" # for debug
TEST_KEYS_ROOT="/srv/chrome-plugin-build/test-keys"
KEY_NAME="test.pem"
WEB_ROOT="/srv/chrome-plugins/${PLUGIN}/${BRANCH}"
WEB_HOST_URL="http://***REMOVED***.***REMOVED***.com"

### chrome packing settings
dir="${BUILD_ROOT}/${PLUGIN}/${PLUGIN}"
key="${TEST_KEYS_ROOT}/${PLUGIN}/${BRANCH}/${KEY_NAME}"
name="$PLUGIN"
crx="$name.crx"
pub="$name.pub"
sig="$name.sig"
zip="$name.zip"

trap 'rm -f "$pub" "$sig" "$zip" "${BUILD_ROOT}/${PLUGIN}"' EXIT

TOOLS="zip openssl printf awk git xxd ssh-agent ssh-add ssh-keygen"

### Validation ####
# check all tools exist
for TOOL in $TOOLS; do
	which $TOOL &>/dev/null || die "ERROR: $TOOL is not installed"
done

# check files / directories exist
for FILE in $REPO_KEY $BUILD_ROOT $TEST_KEYS_ROOT; do
	[ -e $FILE ] || die "ERROR: file or directory $FILE does not exist"
done



### Pull down repo in $BUILD_ROOT - pull fresh each time

ssh-agent bash -c "ssh-add $REPO_KEY &>/dev/null && git clone $REPO_URL ${BUILD_ROOT}/${PLUGIN}" ||\
	die "ERROR: Git clone from $REPO_URL failed"
# assumes if repo branch folder doesn't exist it's branch in web***REMOVED*** also doesn't exist
[ ! -e "$WEB_ROOT" ] && mkdir -p "$WEB_ROOT"

cd "${BUILD_ROOT}/${PLUGIN}"
git checkout "$BRANCH" || die "ERROR: Failed to checkout $BRANCH"

# edit manifest.json
## name with branch appended
sed -i "s/\"name\"[ \t]*:[ \t]*\"\(.*\)\"/\"name\": \"\1-BR: $BRANCH\"/" "${BUILD_ROOT}/${PLUGIN}/${PLUGIN}/manifest.json"
## increment version if autoupdates enables


# edit xml # only needed if want automatic updates, leave off until version increment logic surfaces
## generate app/ext id

## update updatecheck codebase with URL


## increment version - not sure how this will work as would have to increment minor version which would make it out of sync with prod

# check to see if branch directory and key exists and generate folder and key if not exists

[[ ! -d "${TEST_KEYS_ROOT}/${PLUGIN}/${BRANCH}" ]] && mkdir -p "${TEST_KEYS_ROOT}/${PLUGIN}/${BRANCH}" && echo "INFO: $BRANCH folder created"
if [[ ! -f "$key" ]]; then
	cd "${TEST_KEYS_ROOT}/${PLUGIN}/${BRANCH}"
	ssh-keygen -t rsa -b 1024 -f "${KEY_NAME%%.*}" -N ""
	mv "${KEY_NAME%%.*}" "$KEY_NAME"
fi


# chrome package process - create crx

cd "${BUILD_ROOT}"

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
echo "Wrote $crx"

# Move crx to new location (nfs share )
mv "${PLUGIN}.crx" "$WEB_ROOT" || die "ERROR: Failed to transfer crx to webserver"

# cleanup
rm -rf "${BUILD_ROOT}/${PLUGIN}"

echo "INFO: URL to install from:"
echo "=================================================================================================="
echo "${WEB_HOST_URL}/${PLUGIN}/${BRANCH}"
echo "INFO: Browse there and click ${PLUGIN}.crx to install!"
echo "=================================================================================================="