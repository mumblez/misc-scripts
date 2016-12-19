#!/bin/bash
# Add user to groups
# For system administrators, you must add them manually via apache studio (add to global admin group)

die() { echo $* 1>&2 ; exit 1 ; }
DIR=$(cd "$(dirname "$0")" && pwd)

# VALIDATION #
PATH=$PATH:/usr/local/openldap/sbin
which tr  > /dev/null || die "ERROR: tr needs to be installed"
which ldapmodify  > /dev/null || die "ERROR: openldap needs to be installed"

# SETTINGS #
LDAPURL="ldaps://somead:10636"
BASEURL="ou=users,o=cl"
LDAPOPTIONS="-x -H"
# https://someserver/index.php?page=items&group=10&id=17
. /root/scripts/.ldapcreds
FNAME=$(echo @option.first_name@ | tr -d ' ') # aka givenName
SNAME=$(echo @option.last_name@ | tr -d ' ')
DISPLAYNAME="$FNAME $SNAME"
DN="cn=$DISPLAYNAME,$BASEURL"
MAIN_GROUPS_BASE_DN="ou=groups,o=cl"
JIRA_GROUPS_BASE_DN="ou=jira groups,ou=groups,o=cl"
ROLE=@option.role@
# MORE VALIDATION #

# check if user exists
ldapsearch $LDAPOPTIONS $LDAPURL \
-D $BINDUSER -w $BINDPASS \
-b $BASEURL \
'(&(objectClass=inetOrgPerson)(cn='"${DISPLAYNAME}"'))' | grep "dn: $DN" || die "ERROR: User does not exist!"

# FUNCTIONS #

add_to_group() {
GROUP="$1"
case "$2" in
	main ) BASEDN="$MAIN_GROUPS_BASE_DN" ;;
	jira ) BASEDN="$JIRA_GROUPS_BASE_DN" ;;
esac
GROUPDN="cn=${GROUP},${BASEDN}"
ldapmodify $LDAPOPTIONS $LDAPURL \
-D $BINDUSER -w $BINDPASS <<EOF
dn: $GROUPDN
changetype: modify
add: uniqueMember
uniqueMember: $DN
EOF
}

# add to groups
case $ROLE in
	admin )
		add_to_group "admin" "main"
		add_to_group "jira_admins" "jira"
		;;
	dev )
		add_to_group "dev" "main"
		add_to_group "jira_devs" "jira"
		;;
	manager )
		add_to_group "manager" "main"
		add_to_group "jira_admins" "jira"
		;;
	po )
		add_to_group "po" "main"
		add_to_group "jira_pos" "jira"
		;;
	qa )
		add_to_group "qa" "main"
		add_to_group "jira_qas" "jira"
		;;
	senior_dev )
		add_to_group "senior_dev" "main"
		add_to_group "jira_devs" "jira"
		;;
	support )
		add_to_group "support" "main"
		add_to_group "jira_support" "jira"
		;;
esac

# no errors
exit 0
