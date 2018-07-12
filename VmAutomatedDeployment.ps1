############################################################################################
# Script name:     VmAutomatedDeployment.ps1
# Description:     For simple virtual machine container provisioning use only. 
# Version:         1.2
# Date:            02.02.2017
# Author:          Bechtle Steffen Schweiz AG
# History:         02.02.2017 - First tested release
#                  19.07.2017 - Replaced Portgroup for Networkname, diskformat and resource pool based on hostname   
#                  19.07.2017 - Added return value: MAC Address of created VM as requested by customer 
############################################################################################

# Example: # e.g.: .\VmAutomatedDeployment.ps1 -vm_name Test_A053763 -vm_guestid windows9_64Guest -vm_memory 2048 -vm_cpu 2 -vm_network "Server_2037_L2"

param (

    [string]$vm_guestid, # GuestOS identifier from VMware e.g. windows_64Guest for Windows 10 x64
    [string]$vm_name, # Name of the virtual machine
    #[int64]$vm_disk, # System disk size in GB
    [int32]$vm_memory, # Memory size in MB
    [int32]$vm_cpu, # Amount of vCPUs
    [string]$vm_network # Portgroup name to connect
    #[string]$vm_folder # VM Folder location

    # to get the GuestOS identifier run: [VMware.Vim.VirtualMachineGuestOsIdentifier].GetEnumValues()
    # Common Windows versions:
    #-------------------------
    # windows7_64Guest          // Windows 7 (x64)
    # windows7Server64Guest     // Windows Server 2008 R2
    # windows8_64Guest          // Windows 8 (x64)
    # windows8Server64Guest     // Windows Server 2012 R2
    # windows9_64Guest          // Windows 10 (x64)
    # windows9Server64Guest     // Windows Server 2016
)

# clear global ERROR variable
$Error.Clear()

# import vmware related modules, get the credentials and connect to the vCenter server 
Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null
Import-Module -Name VMware.VimAutomation.Vds -ErrorAction SilentlyContinue |Out-Null
$creds = Get-VICredentialStoreItem -file  "C:\scripts\VmAutomatedDeployment\login.creds"
Connect-VIServer -Server $creds.Host -User $creds.User -Password $creds.Password |Out-Null

# define global variables
$init_cluster = 'virtualFrogLab'
$init_datastore = 'VF_ds_01'
$vm_folder = 'VM-Staging'
$current_date = $(Get-Date -format "dd.MM.yyyy HH:mm:ss")
$log_file = "C:\Scripts\VmAutomatedDeployment\log_$(Get-Date -format "yyyyMMdd").txt"
[int64]$vm_disk = 72
$dvPortGroup = Get-VDPortgroup -Name $vm_network

# check if var $VM_NAME already exists in the vCenter inventory

$CheckInventoryByVmName = Get-VM -Name $vm_name -ErrorAction Ignore

if ($CheckInventoryByVmName) {

    Write-Host "This virtual machine already exists!"

} else {

    # check the inputs for provisioning sizing of the virtual machine
    # allowed maximums: 2 vCPU / 8192MB vRAM / 100GB vDISK

    if ($vm_cpu -gt 2) {Write-Host "You input is invalid! (max. 2 vCPUs allowed)"} 
    elseif ($vm_memory -gt 8192) {Write-Host "You input is invalid! (max. 8GB vRAM allowed)"} 
    elseif ($vm_disk -gt 100) {Write-Host "You input is invalid! (max. 100GB vDisk size allowed)"}
    else {

        # create new virtual machine container
        # e.g.: .\VmAutomatedDeployment.ps1 -vm_name Test_A054108 -vm_guestid windows9_64Guest -vm_disk 72 -vm_memory 2048 -vm_cpu 2 -vm_network "Test 10.10.0.0"
        if ($vm_name -like "vm-t*")
        {
            $diskformat = "Thin"
            $init_cluster ="Test"
        }else {
            $diskformat = "Thick"
            $init_cluster = "Production"
        }
        $create_vm = New-VM -Name $vm_name -GuestId $vm_guestid -Location $vm_folder -ResourcePool $init_cluster -Datastore $init_datastore -DiskGB $vm_disk -DiskStorageFormat $diskformat -MemoryMB $vm_memory -NumCpu $vm_cpu -Portgroup $dvPortGroup -CD -Confirm:$false -ErrorAction SilentlyContinue

        # check if virtual machine exists
        if ($create_vm) {
            # change all network adapters to VMXNET3
            $change_vm_network = Get-VM -Name $create_vm | Get-NetworkAdapter | Set-NetworkAdapter -Type Vmxnet3 -Confirm:$false -ErrorAction SilentlyContinue
            
            # check if network adapter exists
            if ($change_vm_network) {
                Add-Content -Path $log_file -Value "$current_date     SCRIPT          $message"
                $macaddress = (get-vm -Name $create_vm |get-networkadapter).MacAddress
            } else {
                Write-Host "There was an unexpected error during the provisioning. For more information see log file: $log_file"
            }
        } else {
            Write-Host "There was an unexpected error during the provisioning. For more information see log file: $log_file"

        }

    }

}

# cleanup and removal of loaded VMware modules
Disconnect-VIServer -Server $creds.Host -Confirm:$false
Remove-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null

# write all error messages to the log file
Add-Content -Path $log_file -Value $Error

#return the MAC address
return $macaddress