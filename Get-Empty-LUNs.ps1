##################################################################################
# Script:           Get-Empty-LUNs.ps1
# Datum:            07.10.2016
# Author:           Bechtle Schweiz AG (c) 2016
# Version:          1.0
# History:          Initial Script
##################################################################################

# vCenter Credentials koennen mit folgendem Command vorgaengig einmalig konfiguriert und hinterlegt werden
# New-VICredentialStoreItem $vCenter
# Default Parameter in erster "Param" Sektion anpassen, ansonnsten werden die hinterlegten Default Werte verwendet


[CmdletBinding(SupportsShouldProcess=$true)]
Param(
  [parameter()]
  [Array]$vCenter = @("vcenter1","vcenter2"),
  # Change to a SMTP server in your environment
  [string]$SmtpHost = "mail.virtualfrog.ch",
# Change to default email address you want emails to be coming from
    [string]$From = "admin@virtualfrog.ch",
# Change to default email address you would like to receive emails
    [Array]$To = @("email1@mail.com","email2@mail.com","email3@mail.com"),
# Change to default Report Filename you like
    [string]$Attachment = "$env:temp\Empty-LUN-Report-"+(Get-Date �f "yyyy-MM-dd")+".csv"
)



Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue | out-null
"C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCliEnvironment.ps1"
Connect-VIServer $vCenter -WarningAction SilentlyContinue | Out-Null
Write-Host "Connected to $vCenter. Starting script"
#foreach ( $cluster in Get-Cluster) {Get-Datastore -RelatedObject $cluster |? {($_ |Get-VM).Count -eq 0 -and $_ -notlike "*rest*" -and $_ -notlike "*_local" -and $_ -notlike "*snapshot*" -and $_ -notlike "*placeholder*"}|select Name, FreeSpaceGB, CapacityGB, @{N="NumVM";E={@($_ |Get-VM).Count}}, @{N="LUN";E={($_.ExtensionData.Info.Vmfs.Extent[0]).DiskName}}, @{N="Cluster";E={@($cluster.Name)}} |Sort Name | Export-CSV $Attachment -Append -NoTypeInformation}

$bodyh = (Get-Date �f "yyyy-MM-dd HH:mm:ss") + "  -  the following Datastores were found to be empty. `n"
$body = foreach ( $cluster in Get-Cluster) {Get-Datastore -RelatedObject $cluster |Where-Object {($_ |Get-VM).Count -eq 0 -and $_ -notlike "*rest*" -and $_ -notlike "*_local" -and $_ -notlike "*snapshot*" -and $_ -notlike "*placeholder*"}|select Name, FreeSpaceGB, CapacityGB, @{N="NumVM";E={@($_ |Get-VM).Count}}, @{N="LUN";E={($_.ExtensionData.Info.Vmfs.Extent[0]).DiskName}}, @{N="Cluster";E={@($cluster.Name)}} |Sort Name }
$body | Export-Csv "$Attachment" -NoTypeInformation -UseCulture
$body = $bodyh + ($body | Out-String)
$subject = "Report - Emtpy Datastores"
send-mailmessage -from "$from" -to $to -subject "$subject" -body "$body" -Attachment "$Attachment" -smtpServer $SmtpHost 
Disconnect-VIServer -Server $vCenter -Force:$true -Confirm:$false