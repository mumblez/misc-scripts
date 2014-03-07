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
USERPASSHASH=$(slappasswd -h {sha} -s $USERPASS)

FNAME=Joe # aka givenName
SNAME=Bloggs
DISPLAYNAME="$FNAME $SNAME"
DN="cn=$DISPLAYNAME,$BASEURL"
# lower case names - tr [A-Z] [a-z]
LUID="$(echo "$FNAME.$SNAME" | tr [A-Z] [a-z])"
EMAIL=$LUID@***REMOVED***.com

# check if user exists
ldapsearch $LDAPOPTIONS $LDAPURL \
-D $BINDUSER -w $BINDPASS \
-b $BASEURL \
'(&(objectClass=inetOrgPerson)(uid='"${LUID}"'))' | grep "uid: $LUID" && die "ERROR: User already exists"

# add user
ldapadd $LDAPOPTIONS $LDAPURL \
-D $BINDUSER -w $BINDPASS <<EOF
dn: $DN
givenName: $FNAME
sn: $SNAME
cn: $DISPLAYNAME
displayName: $DISPLAYNAME
mail: $EMAIL
objectClass: top
objectClass: inetOrgPerson
objectClass: person
objectClass: organizationalPerson
uid: $LUID
userPassword: $USERPASSHASH
EOF

if [ $? = 0 ]
	then 
		echo "SUCCESS: user $DISPLAYNAME added."
	else
		die "ERROR: Failed adding user."
fi

# no errors
exit 0
