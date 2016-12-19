Kills any query running longer than 600 seconds (10 minutes), pt-kill runs daemonised and when it detects a valid query will execute our script (more reliable at killing the query), then will email the team about which query got killed.

Requires percona-toolkit, specifically pt-kill and mysql!

# Setup

* copy pt-kill-exec.sh to /root/scripts/
  * chmod 700 /root/scripts/pt-kill-exec.sh
* copy etc_initd_pt-kill to /etc/init.d/pt-kill
* /etc/init.d/pt-kill start


