<# 
.SYNOPSIS 
    This script will output all Advanced Settings from a esxi host that differ from the default
.DESCRIPTION 
    The script will get all advanced settings that are not at default value from a given esxi host
.NOTES 
    Author     : Dario Dörflinger - virtualfrog.wordpress.com
.LINK 
    http://virtualfrog.wordpress.com
.PARAMETER hostName 
   Name of the host used for source compare (optional)
.PARAMETER delta
   Switch to decide if only values that differ from the default value should get processes
.EXAMPLE 
	C:\foo> .\Get-AdvancedSettingsNotDefault.ps1 -hostName esx01.virtualfrog.lab -delta:$true
	
	Description
	-----------
	Gets All settings that are not at default value from given host
.EXAMPLE 
    C:\foo> .\Get-AdvancedSettingsNotDefault.ps1 -delta:$true
    
    Description
    -----------
    Gets All settings from all hosts that are not at default value    
.EXAMPLE 
    C:\foo> .\Get-AdvancedSettingsNotDefault.ps1 -delta:$false
    
    Description
    -----------
    Gets All settings from all hosts  
#> 

param (
	[Parameter(Mandatory=$False)]
	[string]$hostName="none",
    [Parameter(Mandatory=$False)]
    [boolean]$delta=$false
)

$excludedSettings = "/Migrate/Vmknic|/UserVars/ProductLockerLocation|/UserVars/SuppressShellWarning"
$AdvancedSettings = @()
$AdvancedSettingsFiltered = @()

# Checking if host exists
if ($hostName -ne "none") {
   try {
        $vmhost = Get-VMHost $hostName -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Red "There is no host available with name" $hostName
        exit
    } 

    # Retrieving advanced settings
    $esxcli = $vmhost | get-esxcli -V2
    $AdvancedSettings = $esxcli.system.settings.advanced.list.Invoke(@{delta = $delta}) |select @{Name="Hostname"; Expression = {$vmhost}},Path,DefaultIntValue,IntValue,DefaultStringValue,StringValue,Description

    # Displaying results
    #$AdvancedSettings

} else {
    $vmhosts = get-vmhost
    foreach ($vmhost in $vmhosts) {
        $esxcli = $vmhost | get-esxcli -V2
        $AdvancedSettings += $esxcli.system.settings.advanced.list.Invoke(@{delta = $delta}) |select @{Name="Hostname"; Expression = {$vmhost}},Path,DefaultIntValue,IntValue,DefaultStringValue,StringValue,Description
    }
    #$AdvancedSettings
}

# Browsing advanced settings and check for mismatch
ForEach ($advancedSetting in $AdvancedSettings.GetEnumerator()) {
    if ( ($AdvancedSetting.Path -notmatch $excludedSettings) -And (($AdvancedSetting.IntValue -ne $AdvancedSetting.DefaultIntValue) -Or ($AdvancedSetting.StringValue -notmatch $AdvancedSetting.DefaultStringValue) ) ){
        $line = "" | Select Hostname,Path,DefaultIntValue,IntValue,DefaultStringValue,StringValue,Description
        $line.Hostname = $advancedSetting.Hostname
        $line.Path = $advancedSetting.Path
        $line.DefaultIntValue = $advancedSetting.DefaultIntValue
        $line.IntValue = $advancedSetting.IntValue
        $line.DefaultStringValue = $advancedSetting.DefaultStringValue
        $line.StringValue = $advancedSetting.StringValue
        $line.Description = $advancedSetting.Description
        $AdvancedSettingsFiltered += $line
    }
}
$AdvancedSettingsFiltered