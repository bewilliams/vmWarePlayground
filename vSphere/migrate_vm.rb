require 'rbvmomi'
require 'yaml'

# a helper function to traverse folders
def find_folder (root_object, path) #root is the root vm folder
  folder_path = path.split('/')
  curr_node = root_object
  folder_path.each do |intermediate_folder|
    curr_node = curr_node.childEntity.grep(RbVmomi::VIM::Folder).find { |x| x.name == intermediate_folder } or return nil
  end
  return curr_node
end

#import settings
app_settings = YAML.load_file('config/vsphere_settings.yml')
credentials = app_settings.fetch("vsphere_credentials")

#login to vsphere
vim = RbVmomi::VIM.connect host: credentials["host"], user: credentials["user"], password: credentials["password"] , insecure: credentials["insecure"]

#get the root folder
rootFolder = vim.serviceInstance.content.rootFolder

#get the datacenter
dc = rootFolder.childEntity.grep(RbVmomi::VIM::Datacenter).find { |x| x.name == "Atlanta" } or fail "datacenter not found"

#get the cluster
buster = dc.hostFolder.childEntity.grep(RbVmomi::VIM::ClusterComputeResource).find {|x| x.name == "WGLabs" } or fail "could not find cluster"
#get it? Buster the Cluster!

#get the list of hosts for the cluster
hosts = buster.host

#find the vm
folder = find_folder(dc.vmFolder,'sdk_sandbox/test')
vm = folder.childEntity.grep(RbVmomi::VIM::VirtualMachine).find { |x| x.name == "bob" } or fail "VM not found"

#find the vm's host
#TODO: there has got to be a better way to do this
host = nil
hosts.each do |my_host|
  my_host.vm.each do |my_vm|
    if my_vm == vm
      #we found the host
      host = my_host
    end
  end
end

#remove current host from list, and pick a new host
hosts.delete host
new_host = hosts.sample

#do the motion
task = vm.MigrateVM_Task(:host => new_host, :priority => RbVmomi::VIM::VirtualMachineMovePriority("highPriority"))

#wait for the task to complete
filter = vim.propertyCollector.CreateFilter(
    spec: {
        propSet: [{ type: 'Task', all: false, pathSet: ['info.state']}],
        objectSet: [{ obj: task }]
    },
    partialUpdates: false
)
ver = ''
while true
  result = vim.propertyCollector.WaitForUpdates(version: ver)
  ver = result.version
  break if ['success', 'error'].member? task.info.state
end
filter.DestroyPropertyFilter
raise task.info.error if task.info.state == 'error'
