<#
.SYNOPSIS
  This script takes the notes of each VM and creates a tag from it
 
  To use this script automatically please use the following code to produce a file with the password:
 
  New-VICredentialStoreItem -User $user_name -Password $user_password_decrypted -Host "Somethingsomething" -File "$file_location\login.creds"
 
 .DESCRIPTION
  By taking the notes of each VM and attaching them to the VM as a tag those values will be available to search in html5 client once more
 
.PARAMETER vCenter
  The vCenter to connect to

.PARAMETER tagCategory
    The tagCategory to check attach the tags to (default: "Notes")
 
.INPUTS
  None
 
.OUTPUTS Log File
  The script log file stored in <script-dir>/Set-VMTagFromNotes.log
 
.NOTES
  Version:          1.1
  Author:           Dario Dörflinger
  Creation Date:    19.02.2019
  Purpose/Change:   Initial script development
                    Added function to check tag category existance
 
 
.EXAMPLE
  ./Set-VMTagFromNotes.ps1 -vCenter yourvcenter.yourdomain.com
  Uses the default Tag Category "Notes"

.EXAMPLE
  ./Set-VMTagFromNotes.ps1 -vCenter yourvcenter.yourdomain.com -tagCategory Test
  Overwrites the default TagCategory
#>
 
#---------------------------------------------------------[Script Parameters]------------------------------------------------------
 
Param (
    #Script parameters
    [Parameter(Mandatory = $true)][string]$vCenter,
    [Parameter(Mandatory = $false)][string]$tagCategory = "Notes"
)
 
#---------------------------------------------------------[Initialisations]--------------------------------------------------------
 
#Set Error Action to Silently Continue
$ErrorActionPreference = 'Stop'
 
#Import Modules & Snap-ins
Import-Module PSLogging
 
#----------------------------------------------------------[Declarations]----------------------------------------------------------
 
#Script Version
$sScriptVersion = '1.1'
 
#Log File Info
$sLogPath = $PSScriptRoot
$sLogName = "Set-VMTagFromNotes.log"
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName
 
#-----------------------------------------------------------[Functions]------------------------------------------------------------
Function Connect-VMwareServer {
    Param ([Parameter(Mandatory = $true)][string]$VMServer)
 
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Connecting to vCenter Server [$VMServer]..."
    }
 
    Process {
        Try {
            $oCred = Get-Credential -Message 'Enter credentials to connect to vCenter Server'
            #$oCred = Get-VICredentialStoreItem -File "c:\Set-Resourcepool\login.creds"
            Connect-VIServer -Server $VMServer -User $oCred.User -Password $oCred.password -ErrorAction Stop | Out-Null
        }
 
        Catch {
            Write-LogError -LogPath $sLogFile -Message $_.Exception -ExitGracefully
            Break
        }
    }
 
    End {
        If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
            Write-LogInfo -LogPath $sLogFile -Message ' '
        }
    }
}
 
Function Disconnect-VMwareServer {
    Param ([Parameter(Mandatory = $true)][string]$VMServer)
 
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Disonnecting from vCenter Server [$VMServer]..."
    }
 
    Process {
        Try {
            Disconnect-VIServer -Server $VMServer -Confirm:$false| Out-Null
        }
 
        Catch {
            Write-LogError -LogPath $sLogFile -Message $_.Exception -ExitGracefully
            Break
        }
    }
 
    End {
        If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
            Write-LogInfo -LogPath $sLogFile -Message ' '
        }
    }
}

Function Test-TagCategory {
    Param ([Parameter(Mandatory = $true)][string]$CategoryToCheck)
 
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Checking if Tag Category [$CategoryToCheck] exists..."
    }
 
    Process {
        Try {
            Get-TagCategory -Name $CategoryToCheck | Out-Null
        }
 
        Catch {
            Write-LogInfo -LogPath $sLogFile -Message "Tag Category [$CategoryToCheck] did not exist. Creating it now..."
            New-TagCategory -Name $CategoryToCheck -Cardinality "Multiple" -Description "Category for all converted VM Notes tags" -Confirm:$false
        }
    }
 
    End {
        If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
            Write-LogInfo -LogPath $sLogFile -Message ' '
        }
    }
}
 
 
Function New-TagsFromVMNotes {
    Param ()
 
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message 'Tagging VMs...'
    }
 
    Process {
 
        $i = 0
        $vms = get-vm
        foreach ($currentVm in $vms) {
            Write-Progress -Activity "Converting VM Notes to Tags" -Status ("VM: {0}" -f $currentVm.Name) -PercentComplete ((100 * $i) / ($vms.length - 1)) -Id 1 -ParentId 0
            $notesInfo = $currentVm.Notes
        
            if (($notesInfo -eq "") -or ($null -eq $notesInfo)) {
                Write-LogInfo -LogPath $sLogFile -Message "VM [$currentVM] does not have any Notes..."
                Write-Host -ForegroundColor green "$($currentVM) does not have any notes"
            }
            else {
                try {
                    $tagToSet = get-tag -Name $notesInfo -ErrorAction Stop
                }
                catch {
                    $tagToSet = New-Tag -Name $notesInfo -Category $tagCategory -Confirm:$false
                }
                finally {
                    Write-LogInfo -LogPath $sLogFile -Message "Assigning Tag $($tagToSet) to VM $($currentVM)."
                    New-TagAssignment -Tag $tagToSet -Entity $currentVm -Confirm:$false
                }
            }
            $i++
        }
 
        End {
            If ($?) {
                Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
                Write-LogInfo -LogPath $sLogFile -Message ' '
            }
        }
    }
}
 
#-----------------------------------------------------------[Execution]------------------------------------------------------------
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
Start-Log -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion
Connect-VMwareServer $vCenter
Test-TagCategory $tagCategory
New-TagsFromVMNotes
Disconnect-VMwareServer $vCenter
Stop-Log -LogPath $sLogFile