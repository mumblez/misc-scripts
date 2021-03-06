#!/bin/bash
# Add a new user to our apache DS LDAP directory
# Need to ensure we trim and validate fields/input from rundeck
# hopefully we won't have 2 users with the same names!!!

die() { echo $* 1>&2 ; exit 1 ; }
DIR=$(cd "$(dirname "$0")" && pwd)

# VALIDATION #
PATH=$PATH:/usr/local/openldap/sbin
which tr  > /dev/null || die "ERROR: tr needs to be installed"
which slappasswd  > /dev/null || die "ERROR: openldap needs to be installed"

# SETTINGS #
LDAPURL="ldaps://someserver:10636"
BASEURL="ou=users,o=cl"
LDAPOPTIONS="-x -H"
# https://someserver/index.php?page=items&group=10&id=17
. $DIR/.ldapcreds
USERPASS=@option.last_name@
USERPASSHASH=$(slappasswd -h {sha} -s $USERPASS)
FNAME=$(echo @option.first_name@ | tr -d ' ') # aka givenName
SNAME=$(echo @option.last_name@ | tr -d ' ')
DISPLAYNAME="$FNAME $SNAME"
DN="cn=$DISPLAYNAME,$BASEURL"
LUID="$(echo "$FNAME.$SNAME" | tr [A-Z] [a-z])"
EMAILDOMAIN="cognolink.com"
EMAIL=$LUID@$EMAILDOMAIN

# MORE VALIDATION #

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

# add user to core group(s)
ldapmodify $LDAPOPTIONS $LDAPURL \
-D $BINDUSER -w $BINDPASS <<EOF
dn: cn=user,ou=groups,o=cl
changetype: modify
add: uniqueMember
uniqueMember: $DN
EOF

if [ $? = 0 ]
	then
		echo "SUCCESS: user $DISPLAYNAME added to core groups"
	else
		die "ERROR: Failed adding user to core groups"
fi

# no errors
exit 0
