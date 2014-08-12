#!/usr/bin/python

import gspread, sys
host_name = "dev-blablabla" # change to argument later on
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
  print "***REMOVED***." + wks.cell(free_row, col_ip).value
  sys.exit(0)

# check IP number and assign or output


# set hostname and save

