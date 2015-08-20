#!/usr/bin/python

# requires pysphere library to interact with vmware api
from pysphere import VIServer, VIProperty, VITask, VIException, FaultTypes
from pysphere.vi_mor import VIMor, MORTypes
from time import sleep
import re, sys
import requests


# Settings
vm_template_name = 'dev-wheezy-template'
firstname = "@option.first_name@".lower()
lastname = "@option.last_name@".lower()
#firstname = "robin"
#lastname = "hood"
rundeck_execid = "@job.execid@"
vm_clone_name = "dev-" + firstname[0:1] + lastname
#vm_clone_name = 'dev-kwong' # pass in later (sys.argv[1])
vcenter_server = '***REMOVED***.12'
vcenter_server = 'vcenter'
vcenter_username = '***REMOVED***'           # REPLACE WITH VAULT!!!
vcenter_password = '***REMOVED***'    # REPLACE WITH VAULT
vcenter_folder = 'Dev VMs'
dev_hypervisor = 'vmware-hyp-1.dev.***REMOVED***.com'
#host_datastore = 'SSD-2-1-160'
host_datastore = "@option.datastore@"
verbose = False
maxwait = 120 # How long to keep trying to get clone vm IP address
old_machine = True

# Instantiate server object and connect / create session
server = VIServer()
server.connect(vcenter_server, vcenter_username, vcenter_password)

# Get dev vm template instance
vm_template = server.get_vm_by_name(name=vm_template_name)

# See if dev-vm already exists
try:
    vm_dev = server.get_vm_by_name(name=vm_clone_name)
    old_machine = True
except VIException:
    old_machine = False

#sys.exit(0)

# Delete old machine if found and exists
if old_machine:
    # save datastore info
    old_datastore = vm_dev.get_property(name="path")
    # overwrite and reuse datastore
    host_datastore = old_datastore[1:old_datastore.index(']')]
    print "INFO: old machine found...."
    print "INFO: Shutting down...."
    vm_dev.power_off()
    print "INFO: Deleting...."
    vm_dev.destroy()

# Define our functions
def print_verbose(message):
    if verbose:
        print message

def getHostByName(server, name):
    mor = None
    for host_mor, host_name in server.get_hosts().items():
        if host_name == name: mor = host_mor; break
    return mor

def getResourcePoolByProperty(server, prop, value):
    mor = None
    for rp_mor, rp_path in server.get_resource_pools().items():
        p = server._get_object_properties(rp_mor, [prop])
        if p.PropSet[0].Val == value: mor = rp_mor; break
    return mor

def getDatastoreByName(server, name):
    mor = None
    for ds_mor, ds_path in server.get_datastores().items():
        if ds_path == name: mor = ds_mor; break
    return mor

def find_ip(vm,ipv6=False):
    net_info = None
    waitcount = 0
    while net_info is None:
        if waitcount > maxwait:
            break
        net_info = vm.get_property('net',False)
        print_verbose('Waiting 5 seconds ...')
        waitcount += 5
        sleep(5)
    if net_info:
        for ip in net_info[0]['ip_addresses']:
            if ipv6 and re.match('\d{1,4}\:.*',ip) and not re.match('fe83\:.*',ip):
                print_verbose('IPv6 address found: %s' % ip)
                return ip
            elif not ipv6 and re.match('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',ip) and ip != '127.0.0.1':
                print_verbose('IPv4 address found: %s' % ip)
                return ip
    print_verbose('Timeout expired: No IP address found')
    return None

# Create mor versions of our variables (Managed Object References)
host_mor = getHostByName(server, dev_hypervisor)
prop = server._get_object_properties(host_mor, ['parent'])
parent = prop.PropSet[0].Val
rp_mor = getResourcePoolByProperty(server,"parent", parent)
ds_mor = getDatastoreByName(server, host_datastore)

# Create our clone
print "INFO: Cloning dev template..."
vm_clone = vm_template.clone(name=vm_clone_name, sync_run=True, resourcepool=rp_mor, folder='Dev VMs', host=host_mor, datastore=ds_mor)

# Get the IP address of our new clone (up to maxwait time)
vm_clone_ip = find_ip(vm_clone)

print "INFO: Clone complete, IP: " + vm_clone_ip

# Misc vm actions
# shut down
#vm_clone.power_off()

# destroy / delete
#vm_clone.destroy()

# ADD VM CLONE IP TO etcd
print "INFO: add old IP to etcd..."
url = "http://***REMOVED***.50:4001/v2/keys/rundeck/jobqueue/" + rundeck_execid + "/old_ip"
param = {'value':vm_clone_ip}
requests.put(url, params=param)

# Disconnect from vcenter / hypervisor session
server.disconnect()

# Exit script with 0 (successful)
sys.exit(0)