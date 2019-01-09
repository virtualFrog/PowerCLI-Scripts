<#
.SYNOPSIS
  This script balances resource pools by couting the VMs inside of them
  
  To use this script automatically please use the following code to produce a file with the password:

  New-VICredentialStoreItem -User $user_name -Password $user_password_decrypted -File "$file_location\login.creds"


.DESCRIPTION
  By counting the VMs inside a resource pool this script can effectively balance resource pools according to their requirements

.PARAMETER vCenter
  The vCenter to connect to

.PARAMETER Cluster
  The Cluster in which the resource pools reside

.INPUTS
  None

.OUTPUTS Log File
  The script log file stored in <script-dir>/Set-ResourcePoolsGranular.log

.NOTES
  Version:        1.2
  Author:         Dario Dörflinger
  Creation Date:  22.10.2018
  Purpose/Change: Initial script development
                  Added VICredentialStoreItems for automation of this script
                  Added granularity to account for number of vCPUs and GBs of memory instead of VMs

.EXAMPLE
  ./Set-ResourcePoolsGranular.ps1 -vCenter yourvcenter.yourdomain.com -Cluster yourClusterName
  
  That is it.
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

Param (
  #Script parameters
  [Parameter(Mandatory=$true)][string]$vCenter,
  [Parameter(Mandatory=$true)][string]$Cluster
)

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
$ErrorActionPreference = 'Stop'

#Import Modules & Snap-ins
Import-Module PSLogging

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script Version
$sScriptVersion = '1.2'

#Log File Info
$sLogPath = $PSScriptRoot
$sLogName = "Set-ResourcePoolsGranular.log"
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

$myResourcePools=@(
    [pscustomobject]@{name="1_veryhigh";factor=8},
    [pscustomobject]@{name="2_high";factor=4},
    [pscustomobject]@{name="3_normal";factor=2},
    [pscustomobject]@{name="4_low";factor=1}
    )


#-----------------------------------------------------------[Functions]------------------------------------------------------------
Function Connect-VMwareServer {
    Param ([Parameter(Mandatory = $true)][string]$VMServer)

    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Connecting to vCenter Server [$VMServer]..."
    }

    Process {
        Try {
            $oCred = Get-Credential -Message 'Enter credentials to connect to vCenter Server'
            #$oCred = Get-VICredentialStoreItem -File <path to file>
            Connect-VIServer -Server $VMServer -Credential $oCred -ErrorAction Stop | Out-Null
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
Function OptimizeResourcePools {
    Param ()
  
    Begin {
      Write-LogInfo -LogPath $sLogFile -Message 'Getting all Resource Pools from Cluster...'
    }
  
    Process {
      Try {
            [array]$rPools = Get-ResourcePool -Location (Get-Cluster $Cluster) -ErrorAction Stop
            foreach ($rPool in $rPools) {
                #Do nothing for root resource pool
                if ($rPool.name -ne "Resources") {
                    #Loop through the custom objects
                    foreach ($myPool in $myResourcePools) {
                        #if custom name matches with existing resource pool
                        if ($myPool.name -eq $rPool.name) {
                            $vCPU = Get-VM -Location $rpool | where-object { $_.ExtensionData.Config.ManagedBy.Type -ne "placeholderVm" } | Measure-Object -Property NumCpu -Sum | Select-Object -ExpandProperty Sum
                            $vMem = Get-VM -Location $rpool | where-object { $_.ExtensionData.Config.ManagedBy.Type -ne "placeholderVm" } | Measure-Object -Property MemoryMB -Sum | Select-Object -ExpandProperty Sum
                            $vMemGB = [System.Math]::Round($vMem / 1024)
                            $totalvms = $rpool.ExtensionData.Vm.count

                            Write-LogInfo -LogPath $sLogFile -Message "Total VMs in $($myPool.name): $totalvms"
                            Write-LogInfo -LogPath $sLogFile -Message "Total vCPUs in $($myPool.name): $vCPU"
                            Write-LogInfo -LogPath $sLogFile -Message "Total Memory in $($myPool.name): $vMemGB"
                
                            $rpsharesC = $myPool.factor * $vCPU
                            $rpsharesM = $myPool.factor * $vMemGB
                        
                            # maximum value for share is 4000000
                            if ($rpsharesC -lt 4000000 -and $rpsharesM -lt 4000000)
                                {
                                    Write-LogInfo -LogPath $sLogFile -Message "Setting CPU Shares to $rpsharesC in $($myPool.name)"
                                    Write-LogInfo -LogPath $sLogFile -Message "Setting Memory Shares to $rpsharesM in $($myPool.name)"

                                    #set values
                                    Set-ResourcePool -ResourcePool $rpool.Name -CpuSharesLevel:Custom -NumCpuShares $rpsharesC -MemSharesLevel:Custom -NumMemShares $rpsharesM -Confirm:$False -ErrorAction Stop | Out-Null

                                    #for testing purposes:
                                    #Set-ResourcePool -ResourcePool $rpool.Name -CpuSharesLevel:Custom -NumCpuShares $rpsharesC -MemSharesLevel:Custom -NumMemShares $rpsharesM -Confirm:$False -ErrorAction Stop -WhatIf | Out-Null
                                }
                                else
                                {
                                    Write-LogError -LogPath $sLogFile -Message "Value too high (above 4000000)"
                                }
                        }

                    }
                }

            }
            
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

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Start-Log -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion
Connect-VMwareServer $vCenter
OptimizeResourcePools
Stop-Log -LogPath $sLogFile