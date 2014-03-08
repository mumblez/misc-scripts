#!/bin/bash
# Delete user and all group entries

die() { echo $* 1>&2 ; exit 1 ; }
DIR=$(cd "$(dirname "$0")" && pwd)

# VALIDATION #
PATH=$PATH:/usr/local/openldap/sbin
which tr  > /dev/null || die "ERROR: tr needs to be installed"
which ldapdelete  > /dev/null || die "ERROR: openldap needs to be installed"

# SETTINGS #
LDAPURL="ldaps://***REMOVED***.***REMOVED***.com:10636"
BASEURL="ou=users,o=cl"
LDAPOPTIONS="-x -H"
# https://***REMOVED***.***REMOVED***.com/index.php?page=items&group=10&id=17
. $DIR/.ldapcreds
FNAME=$(echo @option.first_name@ | tr -d ' ') # aka givenName
SNAME=$(echo @option.last_name@ | tr -d ' ')
DISPLAYNAME="$FNAME $SNAME"
DN="cn=$DISPLAYNAME,$BASEURL"
LUID="$(echo "$FNAME.$SNAME" | tr [A-Z] [a-z])"
GROUPS=()

# MORE VALIDATION #

# FUNCTIONS #
# delete from group
del_from_group() {
ldapmodify $LDAPOPTIONS $LDAPURL \
-D $BINDUSER -w $BINDPASS <<EOF
dn: $1
delete: uniqueMember
uniqueMember: $DN
EOF
echo "Removed from group: $1"
}

# check if user exists
ldapsearch $LDAPOPTIONS $LDAPURL \
-D $BINDUSER -w $BINDPASS \
-b $BASEURL \
'(&(objectClass=inetOrgPerson)(uid='"${LUID}"'))' | grep "uid: $LUID" > /dev/null || die "ERROR: User not found!"


# delete user
ldapdelete $LDAPOPTIONS $LDAPURL -D $BINDUSER -w $BINDPASS "$DN" || die "ERROR: Could not delete user!"

# delete user from all groups
ldapsearch $LDAPOPTIONS $LDAPURL -D $BINDUSER -b "o=cl" -w $BINDPASS "(&(objectClass=groupOfUniqueNames)(uniqueMember=${DN}))" | grep "dn:" | cut -c 5- | while read GROUPDN
do
	del_from_group "$GROUPDN"
done

# no errors
exit 0