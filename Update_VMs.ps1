#####################################################################################################################
# Author:           Dario Doerflinger (c) 2015-2018
# Skript:           Update_VMs_1.0.5.ps1
# Datum:            11.10.2017
# Version:          1.0.5
# Original Author:  AFokkema: http://ict-freak.nl/2009/07/15/powercli-upgrading-vhardware-to-vsphere-part-2-vms/
# Changelog:
#                   - Added Support for "noreboot" on VMware Tools install
#                   - Improved Readability and added a general variables section
#                   - Addedd functionality to upgrade VM Version 7 VMs
#                   - Added Snapshot Mechanism to enable Linux Tools Upgrade
#                   - Added functionality to upgrade VM Versions to 11
#                   - Added functionality to upgrade VM Versions to 13 (12 is only for Desktop products)
#                   - Changed Add-Snapin to Import Module (not relevant for PowerCLI 6.5.1)
#
# Summary:          This script will upgrade the VMWare Tools level and the hardware level from VMs
#####################################################################################################################
clear
Write-Host " "
Write-Host " "
Write-Host "######################## Update_VMs_1.0.5.ps1 ##########################"
Write-Host " "
Write-Host "            this script updates  VMware Tools und hardware."
Write-Host " "
Write-Host "######################################################################"
Write-Host " "


Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null
# This script adds some helper functions and sets the appearance.
#"C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCliEnvironment.ps1"


# Variables
$vCenter = Read-Host "Enter your vCenter servername"
#$Folder = Read-Host "Enter the name of the folder where the VMs are stored"
$timestamp = Get-Date -format "yyyyMMdd-HH.mm"
# Note: enter the csv file without extension:
$csvfile = "c:\tmp\$timestamp-vminfo.csv"
$logFile = "c:\tmp\vm-update.log"


#Rotate the Logfile
if (Test-Path $logFile)
{
    if (Test-Path c:\tmp\old_vm-update.log)
    {
        Remove-Item -Path c:\tmp\old_vm-update.log -Force -Confirm:$false
    }
    Rename-Item -Path $logfile -NewName old_vm-update.log -Force -Confirm:$false
}

#LogFunction: Standard at Coop!
function LogWrite
{
    #Aufruf: LogWrite "Tobi ist doof" "INFO" "1"
    Param([string]$logString, [string]$logLevel, [string]$priority)
    $nowDate = Get-Date -Format dd.MM.yyyy
    $nowTime = Get-Date -Format HH:mm:ss

    if ($logLevel -eq "EMPTY")
    {
        Add-Content $logFile -value "$logstring"
        Write-Host $logString
    } else {
        Add-Content $logFile -value "[$logLevel][Prio: $priority][$nowDate][$nowTime] - $logString"
        Write-Host "[$logLevel][Prio: $priority][$nowDate][$nowTime] - $logString"
        
    }

}

################################################################
#       Einlesen der Cred fuer vCenter und ESXi Server          #
################################################################
#$vcCred = C:\vm-scripts\Get-myCredential.ps1 butob C:\vm-scripts\credentials
#$esxCred = C:\vm-scripts\Get-myCredential.ps1 root C:\vm-scripts\host-credential

###############################################################
#                  Prompt for Credentials                      #
################################################################
$vcCred = $host.ui.PromptForCredential("VCENTER LOGIN", "Provide VCENTER credentials (administrator privileges)", "", "")
#$esxCred = $host.ui.PromptForCredential("ESX HOST LOGIN", "Provide ESX host credentials (probably root)", "root", "")


Function Make-Snapshot($vm)
{
  $snapshot = New-Snapshot -VM $vm -Name "BeforeUpgradeVMware" -Description "Snapshot taken before Tools and Hardware was updated" -Confirm:$false

}

Function Delete-Snap()
{
  get-vm | get-snapshot -Name "BeforeUpgradeVMware" | Remove-Snapshot -Confirm:$false
  # $snapshot = Get-Snapshot -Name "BeforeUpgradeVMware" -VM $vm
  # Remove-Snapshot -Snapshot $snapshot -Confirm:$false
}


 
Function VM-Selection
{
   $sourcetype = Read-Host "Do you want to upgrade AllVMs, a VM, Folder, ResourcePool or from a VMfile?"
   if($sourcetype -eq "AllVMs")
   {
      $abort = Read-Host "You've chosen $sourcetype, this is your last chance to abort by pressing <CTRL>+C. Press <ENTER> to continue selecting old hardware VMs"
      #$vms = Get-VM | Get-View | Where-Object {-not $_.config.template -and $_.Config.Version -eq "vmx-08" } | Select Name
      $vms = Get-VM | Get-View | Where-Object {-not $_.config.template} | Select Name
   }
   else
   {
      $sourcename = Read-Host "Give the name of the object or inputfile (full path) you want to upgrade"
      if($sourcetype -eq "VM")
      {
        $abort = Read-Host "You've chosen $sourcetype, this is your last chance to abort by pressing <CTRL>+C. Press <ENTER> to continue selecting old hardware VMs"
        #$vms = Get-VM $sourcename | Get-View | Where-Object {-not $_.config.template -and $_.Config.Version -eq "vmx-08" } | Select Name
        $vms = Get-VM $sourcename | Get-View | Where-Object {-not $_.config.template} | Select Name
      }
      elseif($sourcetype -eq "Folder")
      {
        $abort = Read-Host "You've chosen $sourcetype, this is your last chance to abort by pressing <CTRL>+C. Press <ENTER> to continue selecting old hardware VMs"
        #$vms = Get-Folder $sourcename | Get-VM  | Get-View | Where-Object {-not $_.config.template -and $_.Config.Version -eq "vmx-08" } | Select Name
        $vms = Get-Folder $sourcename | Get-VM  | Get-View | Where-Object {-not $_.config.template} | Select Name
      }
      elseif($sourcetype -eq "ResourcePool")
      {
        $abort = Read-Host "You've chosen $sourcetype, this is your last chance to abort by pressing <CTRL>+C. Press <ENTER> to continue selecting old hardware VMs"
        #$vms = Get-ResourcePool $sourcename | Get-VM  | Get-View | Where-Object {-not $_.config.template -and $_.Config.Version -eq "vmx-08" } | Select Name
        $vms = Get-ResourcePool $sourcename | Get-VM  | Get-View | Where-Object {-not $_.config.template} | Select Name                
      }
      elseif(($sourcetype -eq "VMfile") -and ((Test-Path -path $sourcename) -eq $True))
      {
        $abort = Read-Host "You've chosen $sourcetype with this file: $sourcename, this is your last chance to abort by pressing <CTRL>+C. Press <ENTER> to continue selecting old hardware VMs"
        #$list = Get-Content $sourcename | Foreach-Object {Get-VM $_ | Get-View | Where-Object {-not $_.config.template -and $_.Config.Version -eq "vmx-08" } | Select Name }
        $list = Get-Content $sourcename | Foreach-Object {Get-VM $_ | Get-View | Where-Object {-not $_.config.template} | Select Name }
        $vms = $list
      }
      else
      {
         Write-Host "$sourcetype is not an exact match of AllVMs, VM, Folder, ResourcePool or VMfile, or the VMfile does not exist. Exit the script by pressing <CTRL>+C and try again."
      }
   }
   return $vms
}
 
Function PowerOn-VM($vm)
{
   Start-VM -VM $vm -Confirm:$false -RunAsync | Out-Null
   Write-Host "$vm is starting!" -ForegroundColor Yellow
   sleep 10
 
   do 
   {
    $vmview = get-VM $vm | Get-View
    $getvm = Get-VM $vm
    $powerstate = $getvm.PowerState
    $toolsstatus = $vmview.Guest.ToolsStatus
 
    Write-Host "$vm is starting, powerstate is $powerstate and toolsstatus is $toolsstatus!" -ForegroundColor Yellow
    sleep 5
    #NOTE that if the tools in the VM get the state toolsNotRunning this loop will never end. There needs to be a timekeeper variable to make sure the loop ends
 
    }until(($powerstate -match "PoweredOn") -and (($toolsstatus -match "toolsOld") -or ($toolsstatus -match "toolsOk") -or ($toolsstatus -match "toolsNotInstalled")))
 
    if (($toolsstatus -match "toolsOk") -or ($toolsstatus -match "toolsOld"))
    {
      $Startup = "OK"
      Write-Host "$vm is started and has ToolsStatus $toolsstatus"
    }
    else
    {
      $Startup = "ERROR"
      [console]::ForegroundColor = "Red"
      Read-Host "The ToolsStatus of $vm is $toolsstatus. This is unusual. Press <CTRL>+C to quit the script or press <ENTER> to continue"
      LogWrite "PowerOn Error detected on $vm" "ERROR" "1"
      [console]::ResetColor()
    }
    return $Startup
}
 
Function PowerOff-VM($vm)
{
   Shutdown-VMGuest -VM $vm -Confirm:$false | Out-Null
   Write-Host "$vm is stopping!" -ForegroundColor Yellow
   sleep 10
 
   do 
   {
      $vmview = Get-VM $vm | Get-View
      $getvm = Get-VM $vm
      $powerstate = $getvm.PowerState
      $toolsstatus = $vmview.Guest.ToolsStatus
 
      Write-Host "$vm is stopping with powerstate $powerstate and toolsStatus $toolsstatus!" -ForegroundColor Yellow
      sleep 5
 
   }until($powerstate -match "PoweredOff")
 
   if (($powerstate -match "PoweredOff") -and (($toolsstatus -match "toolsNotRunning") -or ($toolsstatus -match "toolsNotInstalled")))
   {
      $Shutdown = "OK"
      Write-Host "$vm is powered-off"
   }
   else
   {
      $Shutdown = "ERROR"
      [console]::ForegroundColor = "Red"
      Read-Host "The ToolsStatus of $vm is $toolsstatus. This is unusual. Press <CTRL>+C to quit the script or press <ENTER> to continue"
      LogWrite "PowerOff Error detected on $vm" "ERROR" "1"
      [console]::ResetColor()
   }
   return $Shutdown
}
 
Function Check-ToolsStatus($vm)
{
    $vmview = get-VM $vm | Get-View
    $status = $vmview.Guest.ToolsStatus
 
    if ($status -match "toolsOld")
    {
      $vmTools = "Old"
    }
    elseif($status -match "toolsNotRunning")
    {
      $vmTools = "NotRunning"
    }
    elseif($status -match "toolsNotInstalled")
    {
      $vmTools = "NotInstalled"
    }
    elseif($status -match "toolsOK")
    {
      $vmTools = "OK"
    }
    else
    {
      $vmTools = "ERROR"
      Read-Host "The ToolsStatus of $vm is $vmTools. Press <CTRL>+C to quit the script or press <ENTER> to continue"
      LogWrite "VMware Tools Error detected on $vm" "ERROR" "1"
    }
   return $vmTools
}
 
Function Check-VMHardwareVersion($vm)
{
    $vmView = get-VM $vm | Get-View
    $vmVersion = $vmView.Config.Version
    $v7 = "vmx-07"
    $v8 = "vmx-08"
    $v9 = "vmx-09"
    $v10 = "vmx-10"
    $v11 = "vmx-11"
    $v13 = "vmx-13"
    if ($vmVersion -eq $v8)
    {
      $vmHardware = "Old"
    }
    elseif($vmVersion -eq $v7)
    {
      $vmHardware = "Old"
    }
    elseif($vmVersion -eq $v9)
    {
      $vmHardware = "Old"
    }
    elseif($vmVersion -eq $v10)
    {
      $vmHardware = "Old"
    }
    elseif($vmVersion -eq $v11)
    {
      $vmHardware = "Old"
    }
    elseif($vmVersion -eq $v13)
    {
      $vmHardware = "Ok"
    }
    else
    {
      $vmHardware = "ERROR"
      LogWrite "Hardware Version Error detected on $vm" "ERROR" "1"
      [console]::ForegroundColor = "Red"
      Read-Host "The Hardware version of $vm is not set to $v7 or $v8 or $v9 or $v10 or $v11 or $v13. This is unusual. Press <CTRL>+C to quit the script or press <ENTER> to continue"
      [console]::ResetColor()
    }
    return $vmHardware
}
 
Function Upgrade-VMHardware($vm)
{
  $vmview = Get-VM $vm | Get-View
  $vmVersion = $vmView.Config.Version
  $v7 = "vmx-07"
  $v8 = "vmx-08"
  $v9 = "vmx-09"
  $v10 = "vmx-10"
  $v11 = "vmx-11"
  $v13 = "vmx-13"
  
  if ($vmVersion -eq $v7)
  {
    Write-Host "Version 7 detected" -ForegroundColor Red
 
    # Update Hardware
    Write-Host "Upgrading Hardware on" $vm -ForegroundColor Yellow
    Get-View ($vmView.UpgradeVM_Task($v13)) | Out-Null
  }

  if ($vmVersion -eq $v8)
  {
    Write-Host "Version 8 detected" -ForegroundColor Red
 
    # Update Hardware
    Write-Host "Upgrading Hardware on" $vm -ForegroundColor Yellow
    Get-View ($vmView.UpgradeVM_Task($v13)) | Out-Null
  }

  if ($vmVersion -eq $v9)
  {
    Write-Host "Version 9 detected" -ForegroundColor Red
 
    # Update Hardware
    Write-Host "Upgrading Hardware on" $vm -ForegroundColor Yellow
    Get-View ($vmView.UpgradeVM_Task($v13)) | Out-Null
  }

  if ($vmVersion -eq $v10)
  {
    Write-Host "Version 10 detected" -ForegroundColor Red
 
    # Update Hardware
    Write-Host "Upgrading Hardware on" $vm -ForegroundColor Yellow
    Get-View ($vmView.UpgradeVM_Task($v13)) | Out-Null
  }

  if ($vmVersion -eq $v11)
  {
    Write-Host "Version 10 detected" -ForegroundColor Red
 
    # Update Hardware
    Write-Host "Upgrading Hardware on" $vm -ForegroundColor Yellow
    Get-View ($vmView.UpgradeVM_Task($v13)) | Out-Null
  }
}
 
Function CreateHWList($vms, $csvfile)
{
  # The setup for this hwlist comes from http://www.warmetal.nl/powerclicsvvminfo
  Write-Host "Creating a CSV File with VM info" -ForegroundColor Yellow
 
  $MyCol = @()
  ForEach ($item in $vms)
  {
    $vm = $item.Name
    # Variable getvm is required, for some reason the $vm cannot be used to query the host and the IP-address
    $getvm = Get-VM $VM
    $vmview = Get-VM $VM | Get-View
 
    # VM has to be turned on to make sure all information can be recorded
    $powerstate = $getvm.PowerState
    if ($powerstate -ne "PoweredOn")
    {
      PowerOn-VM $vm
    }
 
    $vmnic = Get-NetworkAdapter -VM $VM
    $nicmac = Get-NetworkAdapter -VM $VM | ForEach-Object {$_.MacAddress}
    $nictype = Get-NetworkAdapter -VM $VM | ForEach-Object {$_.Type}
    $nicname = Get-NetworkAdapter -VM $VM | ForEach-Object {$_.NetworkName}
    $VMInfo = "" | Select VMName,NICCount,IPAddress,MacAddress,NICType,NetworkName,GuestRunningOS,PowerState,ToolsVersion,ToolsStatus,ToolsRunningStatus,HWLevel,VMHost
    $VMInfo.VMName = $vmview.Name
    $VMInfo.NICCount = $vmview.Guest.Net.Count
    $VMInfo.IPAddress = [String]$getvm.Guest.IPAddress
    $VMInfo.MacAddress = [String]$nicmac
    $VMInfo.NICType = [String]$nictype
    $VMInfo.NetworkName = [String]$nicname
    $VMInfo.GuestRunningOS = $vmview.Guest.GuestFullname
    $VMInfo.PowerState = $getvm.PowerState
    $VMInfo.ToolsVersion = $vmview.Guest.ToolsVersion
    $VMInfo.ToolsStatus = $vmview.Guest.ToolsStatus
    $VMInfo.ToolsRunningStatus = $vmview.Guest.ToolsRunningStatus
    $VMInfo.HWLevel = $vmview.Config.Version
    $VMInfo.VMHost = $getvm.VMHost
    $myCol += $VMInfo
  }
 
  if ((Test-Path -path $csvfile) -ne $True)
  {
    $myCol |Export-csv -NoTypeInformation $csvfile
  }
  else
  {
    $myCol |Export-csv -NoTypeInformation $csvfile-after.csv
  }
}
 
Function CheckAndUpgradeTools($vm)
{
  $vmview = Get-VM $VM | Get-View
  $family = $vmview.Guest.GuestFamily
  $vmToolsStatus = Check-ToolsStatus $vm
 
  if($vmToolsStatus -eq "OK")
  {
    Write-Host "The VM tools are $vmToolsStatus on $vm"
  }
  elseif(($family -eq "windowsGuest") -and ($vmToolsStatus -ne "NotInstalled"))
  {
    Write-Host "The VM tools are $vmToolsStatus on $vm. Starting update/install now! This will take at few minutes." -ForegroundColor Red
    Get-Date
    Get-VMGuest $vm | Update-Tools -NoReboot
    do
    {
      sleep 10
      Write-Host "Checking ToolsStatus $vm now"
      $vmToolsStatus = Check-ToolsStatus $vm
    }until($vmToolsStatus -eq "OK")
    PowerOff-VM $vm
    PowerOn-VM $vm
  }
  else
  {
    LogWrite "Linux / Windows (no tools installed) detected: $vm" "WARNING" "1"
    # ToDo: If the guest is running windows but tools notrunning/notinstalled it might be an option to invoke the installation through powershell.
    # Options are then Invoke-VMScript cmdlet or through windows installer: msiexec-i "D: \ VMware Tools64.msi" ADDLOCAL = ALL REMOVE = Audio, Hgfs, VMXNet, WYSE, GuestSDK, VICFSDK, VAssertSDK / qn
    # We're skipping all non-windows guest since automated installs are not supported
    # Write-Host "$vm is a $family with tools status $vmToolsStatus. Therefore we're skipping this VM" -ForegroundColor Red

    Write-Host "$vm is a $family with tools status $vmToolsStatus. We are going to do the upgrade, but we'll take a snapshot beforehand"
    if ($vmToolsStatus -ne "NotInstalled")
    {
      Make-Snapshot $vm
      Get-Date
      Get-VMGuest $vm | Update-Tools -NoReboot
      do
      {
        sleep 10
        Write-Host "Checking ToolsStatus $vm now"
        $vmToolsStatus = Check-ToolsStatus $vm
      }until($vmToolsStatus -eq "OK")
      PowerOff-VM $vm
      PowerOn-VM $vm

    }


  }
}
 
Function CheckAndUpgrade($vm)
{
  $vmHardware = Check-VMHardwareVersion $vm
  $vmToolsStatus = Check-ToolsStatus $vm
 
  if($vmHardware -eq "OK")
  {
      Write-Host "The hardware level is $vmHardware on $vm"
  }
  elseif($vmToolsStatus -eq "OK")
  {
      Write-Host "The hardware level is $vmHardware on $vm." -ForegroundColor Red
      $PowerOffVM = PowerOff-VM $vm
      if($PowerOffVM -eq "OK")
      {
          Write-Host "Starting upgrade hardware level on $vm."
          Upgrade-VMHardware $vm
          sleep 5
          PowerOn-VM $vm
          Write-Host $vm "is up to date" -ForegroundColor Green
      }
      else
      {
          Write-Host "There is something wrong with the hardware level or the tools of $vm. Skipping $vm."
      }
  }  
}
 
Connect-VIServer -Server $vcenter -Credential $vcCred -WarningAction SilentlyContinue | out-null
Write-Host "connecting to $vcenter"
 
$vms = VM-Selection
CreateHWList $vms $csvfile
foreach($item in $vms)
{
    $vm = $item.Name
    Write-Host "Test $vm"
    CheckAndUpgradeTools $vm
    CheckAndUpgrade $vm
}
CreateHWList $vms $csvfile
# $toggle = Read-Host "Would you like me to remove the snapshots taken on Linux VMs? (yes/no)"
# if ($toggle -eq "yes")
# {
#   Get-VM | Delete-Snap
# }
Disconnect-VIServer -Confirm:$false
 
