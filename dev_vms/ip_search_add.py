#!/usr/bin/python

# call script passing in firstname lastname rundeck_execID

import gspread, sys
import requests

firstname = "@option.first_name@".lower()
#firstname = "klaus"
lastname = "@option.last_name@".lower()
#lastname = "wong"
rundeck_execid = "@job.execid@"
host_name = "dev-" + firstname[0:1] + lastname # change to argument later on
spread_sheet_key = "someapi"
worksheet = "Dev VLAN"
gc = gspread.login('admin@somecomp.com', 'somepass')
wks = gc.open_by_key(spread_sheet_key).worksheet(worksheet)
dev_hostnames = wks.range('D152:D256')
col_ip = '3'
col_hostnames = '4'
#print wks.acell('A1').value

# find first free slot
for cell in dev_hostnames:
  if not cell.value:
    free_row = cell.row
    break

# search if host name taken in range, catch exception when isn't found and update cell with host name
try:
  wks.find(host_name)
  print "WARNING: host name already exists, re-using IP"
  new_ip = "someip." + wks.cell(wks.find(host_name).row, col_ip).value
except gspread.exceptions.CellNotFound:
  wks.update_cell(free_row,col_hostnames, host_name)
  new_ip = "someip." + wks.cell(free_row, col_ip).value

url = "http://someip:4001/v2/keys/rundeck/jobqueue/" + rundeck_execid + "/ip"
param = {'value':new_ip}
requests.put(url, params=param)
#print new_ip
print "INFO: successfully added IP to etcd"
sys.exit(0)
