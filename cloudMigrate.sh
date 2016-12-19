#!/bin/bash

# undo restrictions in hosts files

sed '/^#/!s/\(.*\)/#\1/' -i /etc/hosts.allow
sed '/^#/!s/\(.*\)/#\1/' -i /etc/hosts.deny

# disable firewall

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT

# change ssh - do by hand
# AllowGroups, password authentication, permitrootlogin, port 22

Port 22
PermitRootLogin yes
PasswordAuthentication yes
AllowGroups itadmins

SSH_CONFIG=/etc/ssh/sshd_config

sed '/^#/!s/Port 6969/Port 22/' -i "$SSH_CONFIG"
sed '/^#/!s/PermitRootLogin no/PermitRootLogin yes/' -i "$SSH_CONFIG"
sed '/^#/!s/PasswordAuthentication no/PermitRootLogin yes/' -i "$SSH_CONFIG"
sed '/^#/!s/AllowGroups itadmins/#AllowGroups itadmins/' -i "$SSH_CONFIG"