<# 
.SYNOPSIS
  This script will help you automate the placement/movement of VMs in resource pools based on a tag.
.DESCRIPTION
  By reading out the assigned resource pool tags the VMs are placed into resource pools with the same name
.NOTES
  Version:          1.0
  Author:           Dario Doerflinger (@virtual_frog)
  Creation Date:    04.04.2019
  Purpose/Change:   Initial script development

The original implementation uses the tag category "ResourcePool". The tags in this category can only be applied to Virtual Machine objects and must be unique (One tag per object). If you need to use another Tag feel free to change the category variable
To use this script automatically please use the following code to produce a file with the password:
New-VICredentialStoreItem -User $user_name -Password $user_password_decrypted -Host "Somethingsomething" -File "$file_location\login.creds"
.LINK
    https://virtualfrog.wordpress.com
.PARAMETER vCenter
  The vCenter to connect to
.PARAMETER DefaultTag
  Parameter to tag VMs that have no tags assigned
  Default: $null
.INPUTS
  None
.OUTPUTS
  The script log file stored in <script-dir>/Move-VMsIntoResoucePoolsBasedOnTag.log
.EXAMPLE
  ./Move-VMsIntoResoucePoolsBasedOnTag.ps1 -vCenter yourvcenter.yourdomain.com
  Will iterate through each cluster and move VMs into resource pools
.EXAMPLE
  ./Move-VMsIntoResoucePoolsBasedOnTag.ps1 -vCenter yourvcenter.yourdomain.com -DefaultTag "2_Normal"
  Will first check if there are VMs without assigned Tags from the "ResourcePool" Category and assign the "2_Normal" Tag (will be created if it does not exist)
  Will iterate through each cluster and move VMs into resource pools

#>
 
#---------------------------------------------------------[Script Parameters]------------------------------------------------------
 
Param (
    #Script parameters
    [Parameter(Mandatory = $true)][string]$vCenter,
    [Parameter(Mandatory = $false)][string]$defaultTag = $null
)
 
#---------------------------------------------------------[Initialisations]--------------------------------------------------------
 
#Set Error Action to Stop
$ErrorActionPreference = 'Stop'
 
#Import Module for Logging
Import-Module PSLogging
 
#----------------------------------------------------------[Declarations]----------------------------------------------------------
 
#Script Version
$sScriptVersion = '1.0'
 
#Log File Info
$sLogPath = $PSScriptRoot
$sLogName = "Move-VMsIntoResoucePoolsBasedOnTag.log"
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName
 
#Default Tag Category name
$defaultTagCategoryName = "ResourcePool"

#-----------------------------------------------------------[Functions]------------------------------------------------------------
Function Connect-VMwareServer {
    Param ([Parameter(Mandatory = $true)][string]$VMServer)
 
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Connecting to vCenter Server [$VMServer]..."
    }
 
    Process {
        Try {
            $oCred = Get-Credential -Message 'Enter credentials to connect to vCenter Server'
            Connect-VIServer -Server $VMServer -Credential $oCred -ErrorAction Stop | Out-Null

            #Use the below to automate the login with a VI Credential File
            #$oCred = Get-VICredentialStoreItem -File "c:\Set-Resourcepool\login.creds"
            #Connect-VIServer -Server $VMServer -User $oCred.User -Password $oCred.password -ErrorAction Stop | Out-Null
        }
 
        Catch {
            Write-LogError -LogPath $sLogFile -Message $_.Exception -ExitGracefully
            Break
        }
    }
 
    End {
        If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Connect-VMwareServer Successfully.'
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
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Disconnect-VMwareServer Successfully.'
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
            New-TagCategory -Name $CategoryToCheck -Cardinality "Single" -Description "Category for resource pool assignment" -Confirm:$false | Out-Null
        }
    }
 
    End {
        If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Test-TagCategory Successfully.'
            Write-LogInfo -LogPath $sLogFile -Message ' '
        }
    }
}

Function Test-Tag {
    Param ([Parameter(Mandatory = $true)][string]$TagToCheck)
 
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Checking if Tag [$TagToCheck] exists..."
    }
 
    Process {
        Try {
            $returningThis = Get-Tag -Name $TagToCheck

        }
 
        Catch {
            Write-LogInfo -LogPath $sLogFile -Message "Tag [$TagToCheck] did not exist. Creating it now..."
            $returningThis = New-Tag -Name $TagToCheck -Category $defaultTagCategoryName -Description "Tag for VMs to move into corresponding Resource pool" -Confirm:$false
        }
    }
 
    End {
        If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Test-Tag Successfully.'
            Write-LogInfo -LogPath $sLogFile -Message ' '
            return $returningThis
        }
    }
}

Function Test-ResourcePool {
    Param ([Parameter(Mandatory = $true)][string]$ResourcePoolToCheck,
        [Parameter(Mandatory = $true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.ComputeResourceImpl]$ClusterObject)
 
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Checking if resource pool [$ResourcePoolToCheck] exists in cluster [$ClusterObject]..."
    }
 
    Process {
        Try {
            Get-ResourcePool -Name $ResourcePoolToCheck -Location $ClusterObject | Out-Null
        }
 
        Catch {
            Write-LogInfo -LogPath $sLogFile -Message "Resource pool [$ResourcePoolToCheck] did not exist in cluster [$ClusterObject]. Creating it now..."
            New-ResourcePool -Name $ResourcePoolToCheck -Location $ClusterObject -Confirm:$false | Out-Null
        }
    }
 
    End {
        If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Test-ResourcePool Successfully.'
            Write-LogInfo -LogPath $sLogFile -Message ' '
        }
    }
}

Function Set-DefaultTag {
    Param ([Parameter(Mandatory = $true)][string]$defaultTag)
 
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Checking if all tags have a resource pool tag and if one does not have one attach the tag [$defaultTag] to it ..."
    }
 
    Process {
        $tag = Test-Tag $defaultTag
        foreach ($currentVM in Get-VM) {
            if ($null -eq (Get-TagAssignment -Category $defaultTagCategoryName -Entity $currentVM)) {
                Write-LogInfo -LogPath $sLogFile -Message "VM [$currentVM] did not have a resource pool tag. Tagging it with [$defaultTag]..."
                New-TagAssignment -Entity $currentVM -Tag $tag -Confirm:$false | Out-Null
            }
        }
        
    }
 
    End {
        If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Set-DefaultTag Successfully.'
            Write-LogInfo -LogPath $sLogFile -Message ' '
        }
    }
}
 
 
 
Function Move-VMsIntoResoucePoolsBasedOnTag {
    Param ()
 
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message 'Moving VMs into resource pools...'
    }
 
    Process {

        Test-TagCategory $defaultTagCategoryName
        if ($null -ne $defaultTag) {
            Set-DefaultTag $defaultTag
        }
       
        $i = 0
        $allClusters = Get-Cluster
        foreach ($currentCluster in $allClusters) {
            Write-Progress -Activity "Moving VMs into Resource Pools" -Status ("Cluster: {0}" -f $currentCluster.Name) -PercentComplete ((100 * $i) / ($allClusters.length)) -Id 1 -ParentId 0
            $currentCluster | Get-VM | Get-TagAssignment -Category $defaultTagCategoryName | ForEach-Object {
                Test-ResourcePool $_.Tag.Name $currentCluster
                Write-LogInfo -LogPath $sLogFile -Message "Moving VM $($_.Entity.Name) into resource pool $($_.Tag.Name) in Cluster $($currentCluster)..." 
                (Get-ResourcePool -Name $_.Tag.Name -Location $currentCluster).ExtensionData.MoveIntoResourcePool((get-vm -Name $_.Entity.Name).ExtensionData.MoRef)
                If ($?) {
                    Write-LogInfo -LogPath $sLogFile -Message "Completed moving VM $($_.Entity.Name) into resource pool $($_.Tag.Name) in Cluster $($currentCluster) Successfully."
                    Write-LogInfo -LogPath $sLogFile -Message ' '
                }
            }
            $i++
        }
    }

    End {
        If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Move-VMsIntoResoucePoolsBasedOnTag Successfully.'
            Write-LogInfo -LogPath $sLogFile -Message ' '
        }
    }
    
}
 
#-----------------------------------------------------------[Execution]------------------------------------------------------------
#Some housekeeping
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

Start-Log -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion
Connect-VMwareServer $vCenter
Move-VMsIntoResoucePoolsBasedOnTag
Disconnect-VMwareServer $vCenter
Stop-Log -LogPath $sLogFile