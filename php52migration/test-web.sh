#!/bin/bash

echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="00:50:56:8c:ab:cc", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="eth*", NAME="eth1"' >> /etc/udev/rules.d/70-persistent-net.rules

cp -f ./test-hosts /etc/hosts

# give ourselves access as this is a clone
cd new_vhost_confs
for i in `ls`; do
    sed '/Allow from 10.10./s/\#//' -i $i
done

echo "should reboot!!!"
echo "should also uncomment our IPs to intranet, zaibatsu, restserver...."
