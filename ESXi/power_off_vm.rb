require 'rbvmomi'
require 'yaml'

#import settings
app_settings = YAML.load_file('config/settings.yml')
credentials = app_settings.fetch("credentials")

#login to vsphere
vim = RbVmomi::VIM.connect host: credentials["host"], user: credentials["user"], password: credentials["password"] , insecure: credentials["insecure"]

#get the root folder
rootFolder = vim.serviceInstance.content.rootFolder

#get the datacenter
dc = rootFolder.childEntity.grep(RbVmomi::VIM::Datacenter).find { |x| x.name == "ha-datacenter" } or fail "datacenter not found"

#find the vm
vm = dc.vmFolder.childEntity.grep(RbVmomi::VIM::VirtualMachine).find { |x| x.name == "nothere" } or fail "VM not found"

#power off the VM
task = vm.PowerOffVM_Task

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
