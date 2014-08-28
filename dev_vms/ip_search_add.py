#!/usr/bin/python

# call script passing in firstname lastname rundeck_execID

import gspread, sys
import requests

firstname = "@option.first_name@"
lastname = "@option.last_name@"
rundeck_execid = "@job.execid@"
host_name = "dev-" + firstname[0:1] + lastname # change to argument later on
spread_sheet_key = "***REMOVED***"
worksheet = "Dev VLAN"
gc = gspread.login('admin@***REMOVED***.com', '***REMOVED***')
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
  print "host name already exists"
  sys.exit(1)
except gspread.exceptions.CellNotFound:
  wks.update_cell(free_row,col_hostnames, host_name)
  new_ip = "***REMOVED***." + wks.cell(free_row, col_ip).value
  url = "http://***REMOVED***.50:4001/v2/keys/rundeck/jobqueue/" + rundeck_execid + "/ip"
  param = {'value':new_ip}
  requests.put(url, params=param)
  sys.exit(0)

# add IP to etcd (use execid) with low TTL
#http://stackoverflow.com/questions/4476373/simple-url-get-post-function-in-python
#import requests
#url = "http://127.0.0.1:4001/v2/keys/bbb"
#param = {'value':'bye george'}
#r = requests.put(url, params=param)


# set hostname and save

