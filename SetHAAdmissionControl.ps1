<#
.SYNOPSIS
  This script sets the HA admission control to the percentage setting taking into account the number of hosts the user wnats to tolerate

.DESCRIPTION
  as a parameter you provide the number of hosts failures you want to tolerate, the name of the cluster and the name of the vCenter server
  the script will then set the admission control to the percentage value according to the number of hosts in the cluster
  the script will detect if there is a uneven set of resources in the cluster per host and display a warning. it will then base the calculations on the biggest host in the cluster.

  Important: this script is intended to for vSphere prior to 6.5. Starting with vSphere 6.5 this functionality is built in

.PARAMETER vCenter
    vCenter Server to connect to (example: bezhvcs03.bechtlezh.ch)

.PARAMETER cluster
    Name of the cluster on which this setting will be applied (example: CLTEST)

.PARAMETER failuresToTolerate
    Number of host failures to tolerate (example: 1)

.INPUTS
  Parameters above

.OUTPUTS
  Log file stored in $sLogPath\$sLogName

.NOTES
  Version:        1.0
  Author:         Dario Dörflinger (aka. virtualFrog)
  Creation Date:  08.05.2018
  Purpose/Change: Script requested to frequently update the HA Admission setting if the number of hosts in a cluster changes
  
.EXAMPLE
  SetHAAdmissionControl.ps1 -vCenter bezhvcs03.bechtlezh.ch -cluster CLTEST -failuresToTolerate 1
  Sets the correct percentages for 1 failure on cluster CLTEST in vCenter bezhvcs03.bechtlzh.ch
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

Param (
    #Script parameters go here
    [Parameter(Mandatory = $true)][string]$vCenter,
    [Parameter(Mandatory = $true)][string]$cluster,
    [Parameter(Mandatory = $true)][string]$failuresToTolerate
)

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
$ErrorActionPreference = 'SilentlyContinue'

#Import Modules & Snap-ins
Import-Module PSLogging

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script Version
$sScriptVersion = '1.0'

#Log File Info
$sLogPath = 'C:\Temp'
$sLogName = 'HA_AdmissionControlLog.log'
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
            Connect-VIServer -Server $VMServer -Credential $oCred -ErrorAction Stop
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


Function checkRAMCompliance {
    Param ([Parameter(Mandatory = $true)][string]$clusterName)
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Checking if all hosts in cluster [$clusterName] have the same amount of RAM..."
        $myHostsRAM = @()
    }
    Process {
        Try {
            $clusterObject = Get-Cluster -Name $clusterName -ErrorAction Stop
            $hostObjects = $clusterObject | Get-VMHost -ErrorAction Stop

            foreach ($hostObject in $hostObjects) {

                $HostInfoMEM = "" | Select-Object MEM

                $HostInfoMEM.MEM = $hostObject.MemoryTotalGB

                $myHostsRAM += $HostInfoMEM
            }
            #Check if all values are correct: return true, otherwise return false
            if (@($myHostsRAM | Select-Object -Unique).Count -eq 1) {
                #CPU are the same
                Write-LogInfo -LogPath $sLogFile -Message "RAM in the cluster is the same"
                return $true
            }
            else {
                Write-LogInfo -LogPath $sLogFile -Message "RAM in the cluster is NOT the same"
                return $false
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


Function checkCPUCompliance {
    Param ([Parameter(Mandatory = $true)][string]$clusterName)
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Checking if all hosts in cluster [$clusterName] have the same CPU..."
        $myHostsCPU = @()
    }
    Process {
        Try {
            $clusterObject = Get-Cluster -Name $clusterName -ErrorAction Stop
            $hostObjects = $clusterObject | Get-VMHost -ErrorAction Stop

            foreach ($hostObject in $hostObjects) {
                $HostInfoCPU = "" | Select-Object CPU

                $HostInfoCPU.CPU = $hostObject.CpuTotalMhz

                $myHostsCPU += $HostInfoCPU
            }
            #Check if all values are correct: return true, otherwise return false

            if (@($myHostsCPU | Select-Object -Unique).Count -eq 1) {
                Write-LogInfo -LogPath $sLogFile -Message "CPU in the cluster is the same"
                return $true              
            }
            else {
                Write-LogInfo -LogPath $sLogFile -Message "CPU in the cluster is NOT the same"
                return $false
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

Function getBiggestCPUInCluster {
    Param ([Parameter(Mandatory=$true)][string]$clusterName)
    Begin {
      Write-LogInfo -LogPath $sLogFile -Message "Trying to get the biggest CPU resource in cluster [$clusterName]..."
    }
    Process {
      Try {
        $clusterObject = Get-Cluster $clusterName -ErrorAction Stop
        $hostObjects = $clusterObject | Get-VMHost -ErrorAction Stop
        $cpuResources =  @()
        foreach ($hostObject in $hostObjects) {
            $cpuInfo = "" | Select-Object CPU
            $cpuInfo.CPU = $hostObject.CpuTotalMhz

            $cpuResources += $cpuInfo
        }
        return ($cpuResources | Measure-Object -Maximum)

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

  Function getBiggestRAMInCluster {
    Param ([Parameter(Mandatory=$true)][string]$clusterName)
    Begin {
      Write-LogInfo -LogPath $sLogFile -Message "Trying to get the biggest RAM resource in cluster [$clusterName]..."
    }
    Process {
      Try {
        $clusterObject = Get-Cluster $clusterName -ErrorAction Stop
        $hostObjects = $clusterObject | Get-VMHost -ErrorAction Stop
        $ramResources =  @()
        foreach ($hostObject in $hostObjects) {
            $ramInfo = "" | Select-Object RAM
            $ramInfo.RAM = $hostObject.MemoryTotalGB

            $ramResources += $ramInfo
        }
        return ($ramResources | Measure-Object -Maximum)

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

Function SetAdmissionControl {
    Param ([Parameter(Mandatory = $true)][string]$clusterName)
    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "Setting the admission policy on cluster [$clusterName].."
    }
    Process {
        Try {
            $RAMCompliance = checkRAMCompliance $clusterName
            $CPUCompliance = checkCPUCompliance $clusterName
            $totalAmountofHostsInCluster = (Get-Cluster -Name $clusterName -ErrorAction Stop | Get-VMHost -ErrorAction Stop).Count
            if (($RAMCompliance -eq $true) -and ($CPUCompliance -eq $true)) {
                #Same hardware. calculation very simple
                [int]$ramPercentageToReserve = [math]::Round((100 / ($totalAmountofHostsInCluster) * ($failuresToTolerate)), 0)
                [int]$cpuPercentageToReserve = [math]::Round((100 / ($totalAmountofHostsInCluster) * ($failuresToTolerate)), 0)

            }
            if ($CPUCompliance -eq $false) {
                #calculate with different CPU resources but same RAM resources
                #get biggest CPU amount, total amount and number of hosts in cluster
                $biggestCPUValue = getBiggestCPUInCluster $clusterName
                $totalCPUMhz = (Get-Cluster $clusterName).ExtensionData.Summary.TotalCPU

                [int]$cpuPercentageToReserve = [math]::Round(((($biggestCPUValue) * 100) / ($totalCPUMhz)*($failuresToTolerate)),0)
            }
            if ($RAMCompliance -eq $false) {
                #in this case RAM is the decisive factor
                #get biggest RAM amount, total amount and number of hosts in cluster
                $biggestMemoryValue = getBiggestRAMInCluster $clusterName
                $totalMemoryGB = [math]::Round(((Get-Cluster $clusterName).ExtensionData.Summary.TotalMemory /1024 /1024 /1024),0)
                
                [int]$ramPercentageToReserve = [math]::Round(((($biggestMemoryValue) * 100) / ($totalMemoryGB)*($failuresToTolerate)),0)
            }

            Write-LogInfo -LogPath $sLogFile -Message "CPU Value calculated: [$cpuPercentageToReserve].."
            Write-LogInfo -LogPath $sLogFile -Message "RAM Value calculated: [$ramPercentageToReserve].."

            $spec = New-Object VMware.Vim.ClusterConfigSpecEx
            $spec.dasConfig = New-Object VMware.Vim.ClusterDasConfigInfo
            $spec.dasConfig.AdmissionControlPolicy = New-Object VMware.Vim.ClusterFailoverResourcesAdmissionControlPolicy
            $spec.dasConfig.AdmissionControlEnabled = $true
            $spec.dasConfig.AdmissionControlPolicy.cpuFailoverResourcesPercent = $cpuPercentageToReserve
            $spec.dasConfig.AdmissionControlPolicy.memoryFailoverResourcesPercent = $ramPercentageToReserve

            $clusterObject = Get-Cluster $clusterName
            $clusterView =  Get-View $clusterObject
            $clusterView.ReconfigureComputeResource_Task($spec, $true)
            
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
Connect-VMwareServer -VMServer $vCenter
SetAdmissionControl -clusterName $cluster
Stop-Log -LogPath $sLogFile