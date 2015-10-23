#!/bin/bash

# intended to add self signed Cognolink CA public cert
# to server.
die() { echo $* 1>&2 ; exit 1 ; }

[ $USER != "***REMOVED***" ] && die "You must be ***REMOVED***!, good bye"

# Detect OS

#CA_PKG="ca-certificates"
#CA_CRT_URL="http://***REMOVED***.52/cl***REMOVED***ca.pem"
#CA_CRT_DEST_NAME="cl***REMOVED***ca.crt"
CA_CRT_DEST_NAME="$1"
#which wget || die "Please install wget and try again"

# if centos / redhat
if [ -e /etc/redhat-release ]; then
	echo "CentOS / RHEL OS detected"
	echo "Checking if ca-certificates is installed."
	rpm -qa | grep -q "$CA_PKG" || yum install "$CA_PKG"
	[ $? -eq 0 ]  || die "Failed to install $CA_PKG"
	# check cert doesn't already exist
	CA_PATH="/etc/pki/ca-trust/source/anchors"
	CA_FULL_PATH="${CA_PATH}/${CA_CRT_DEST_NAME}"
	if [ ! -e "$CA_FULL_PATH" ]; then
		# download and add the cert
		# wget -O "$CA_FULL_PATH" "$CA_CRT_URL" # place file using file.managed - salt
		update-ca-trust enable
		update-ca-trust extract
	else
		echo "Cert already exists @ $CA_FULL_PATH, skipping!"
		exit 0
	fi


elif [ -e /etc/debian_version ]; then
	echo "Debian OS detected"
	echo "Checking if ca-certificates is installed."
	dpkg -l | grep -q "$CA_PKG" || apt-get install "$CA_PKG"
	# check cert doesn't already exit
	CA_PATH="/usr/local/share/ca-certificates"
	CA_FULL_PATH="${CA_PATH}/${CA_CRT_DEST_NAME}"
	if [ ! -e "$CA_FULL_PATH" ]; then
		# download and add the cert
		# wget -O "$CA_FULL_PATH" "$CA_CRT_URL" # place file using file.managed - salt
		update-ca-certificates
	else
		echo "Cert already exists @ $CA_FULL_PATH, skipping!"
		exit 0
	fi
else
	echo "Unsupported OS, no actions taken!"
	exit 1
fi

exit 0