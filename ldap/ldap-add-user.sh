#!/bin/bash
die() { echo $* 1>&2 ; exit 1 ; }
# ldapsearch -x -v -H ldaps://***REMOVED***.***REMOVED***.com:10636 -D "cn=ssp,ou=services,o=cl" -b "ou=users,o=cl" -w <pass>
#git archive --remote=git@***REMOVED***.***REMOVED***.com:infrastructure/scripts.git master:repos/dnb --format=tar description | tar xf -
# ldapsearch -x -H ldaps://***REMOVED***.***REMOVED***.com:10636 -D "cn=ldap_mgt,ou=services,o=cl" -b "ou=users,o=cl" -w <pass> '(&(objectClass=inetOrgPerson)(uid=***REMOVED***))'

# hopefully we won't have 2 users with the same names!!!

# SETTINGS #
LDAPURL="ldaps://***REMOVED***.***REMOVED***.com:10636"
BASEURL="ou=users,o=cl"
LDAPOPTIONS="-x -H"
BINDUSER="cn=ldap_mgt,ou=services,o=cl"
# https://***REMOVED***.***REMOVED***.com/index.php?page=items&group=10&id=17
BINDPASS=
USERPASS=

FNAME=Joe # aka givenName
SNAME=Bloggs
DISPLAYNAME="$FNAME $SNAME"
DN="$DISPLAYNAME,$BASEURL"
# lower case names - tr [A-Z] [a-z]
UID=$(echo $FNAME | tr [A-Z] [a-z]).$(echo $SNAME | tr [A-Z] [a-z])
EMAIL=$UID@***REMOVED***.com

# check if user exists
ldapsearch $LDAPOPTIONS $LDAPURL \
-D $BINDUSER -w $BINDPASS \
-b $BASEURL \
'(&(objectClass=inetOrgPerson)(uid='"${UID}"'))' | grep "uid: $UID" && die "ERROR: User already exists"

# add user
ldapadd $LDAPOPTIONS $LDAPURL \
-D $BINDUSER -w $BINDPASS \
-b $BASEURL <<EOF
dn: $DN
givenName: $FNAME
sn: $SNAME
cn: $DISPLAYNAME
displayName: $DISPLAYNAME
uid: $UID
mail: $EMAIL
objectClass: top
objectClass: inetOrgPerson
objectClass: person
objectClass: organizationalPerson
EOF && "SUCCESS: user $DISPLAYNAME added." || die "ERROR: Failed adding user."


# no errors
exit 0