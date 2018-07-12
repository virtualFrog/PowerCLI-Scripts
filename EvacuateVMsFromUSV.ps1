############################################################################################
# Script name:     EvacuateVMsFromUSV.ps1
# Description:     Evacuate all VMs from one site in a active-active cluster and shut down the Hosts
# Version:         1.0
# Date:            20.07.2017
# Author:          Bechtle Steffen Schweiz AG | Dario Doerflinger (virtualfrog.wordpress.com)
# History:         20.07.2017 - First tested release 
############################################################################################

# Example: # e.g.: .\EvacuateVMsFromUSV.ps1 -SiteToShutdown Allschwil

param (
    [string]$SiteToShutdown # Identifier of site
)
$vCenter_server = "bezhvcs03.bechtlezh.ch"
# clear global ERROR variable
$Error.Clear()

# import vmware related modules, get the credentials and connect to the vCenter server 
Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null
Import-Module -Name VMware.VimAutomation.Vds -ErrorAction SilentlyContinue |Out-Null
$creds = Get-VICredentialStoreItem -file  "C:\Users\Administrator\Desktop\login.creds"
Connect-VIServer -Server $vCenter_server -User $creds.User -Password $creds.Password |Out-Null

# define global variables

$current_date = $(Get-Date -format "dd.MM.yyyy HH:mm:ss")
$log_file = "C:\Users\Administrator\Desktop\\log_$(Get-Date -format "yyyyMMdd").txt"


Function SetDRStoAutomatic ($cluster)
{
    try {
        $cluster | Set-Cluster -DrsEnabled:$true -DrsAutomationLevel FullyAutomated -Confirm:$false |Out-Null
    } catch {
        Write-Host -Foregroundcolor:red "Could not set DRS Mode to automatic"
    }
}

Function RemoveRemovableMediaFromVMs($esxhost)
{
    try {
        $esxhost | Get-VM | Where-Object {$_.PowerState –eq “PoweredOn”} | Get-CDDrive | Set-CDDrive -NoMedia -Confirm:$False |Out-Null
        
    } catch {
        Write-Host -Foregroundcolor:red "Could not get the vm objects from host."
    }
}

Function EvacuateVMsFromHost($esxhost)
{
    try {
        $esxhost | Set-VMHost -State Maintenance -Evacuate:$true -Confirm:$false |Out-Null
    } catch {
        Write-Host -Foregroundcolor:red "Could not put host into maintenance mode"
    }
}

Function ShutDownHost($esxhost)
{
    try {
       $esxhost | Stop-VMhost -Confirm:$false -Whatif 
    } catch {
        Write-Host -Foregroundcolor:red "Could not shut down host"
    }
}


###### Main Program ######
if ($SiteToShutdown -eq "Allschwil") {
    $hosts = @("bezhesx40.bechtlezh.ch")
    
} elseif ($SiteToShutdown -eq "Pratteln")
{
    $hosts = @("bezhesx41.bechtlezh.ch")
}

foreach ($esxhost in $hosts)
{
    $cluster = (get-vmhost $esxhost).Parent
    SetDRStoAutomatic($cluster)

    $esxihost = Get-VMhost $esxhost
    RemoveRemovableMediaFromVMs($esxihost)
    EvacuateVMsFromHost($esxihost)
    ShutDownHost($esxihost)
}


# cleanup and removal of loaded VMware modules
Disconnect-VIServer -Server $vCenter_server -Confirm:$false |Out-Null
Remove-Module -Name VMware.VimAutomation.Vds -ErrorAction SilentlyContinue | Out-Null
Remove-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null


# write all error messages to the log file
Add-Content -Path $log_file -Value $Error
