<#
.SYNOPSIS
	Run various networking tests on all hosts in a cluster, using a test VM.
	Can be run on a dvSwitch or a Standard Switch
.DESCRIPTION
	Using a Microsoft Windows test VM, iterate through a list of port groups and 
	subnets (specified in the CSV input file) and run tests.
	Testing method involves assigning the test VM to a specific port group or VLAN ID,
	assigning IP information and running a test ping.
	
	Currently, performs the following tests:		
		Test connectivity with VM on each port group
        Test connectivity for each VLAN ID on each uplink on each host in the cluster.
    
    Requirements:
        UAC disabled on Windows testVM
        PowerCLI 6.5 or higher
        testVM language must be english or the ping command outputs cannot be parsed correctly
.PARAMETER clusterName
    Input - Clustername you want to test
.PARAMETER dvsName
    Input - Name of the vSwitch/DVS you want to test.
    E.g.: vSwitch0 or dvs-01
.PARAMETER isStandard
    Input - is it a standardswitch?
    E.g.: -isStandard:$false for a dvSwitch
    - isStandard:$true for a standard switch
.PARAMETER resultfile
    Input - Path to the CSV that will save the output of the script
.PARAMETER csvFile
	Input - CSV file containing IP info to test.  Must contain the following columns.
		Port Group - a valid port group name available on the specified DVS
		Source IP - IP to assign to the test VM for this port group
		Gateway IP - Gateway to assign to the test VM
		SubnetMask - Subnet mask to assign to test VM
		Test IP - IP address to target for ping test
		
	This is example data:
	PortGroup,SourceIP,GatewayIP,SubnetMask,TestIP
	PG_NET1,10.10.101.55,10.10.101.1,255.255.255.0,10.0.0.1
	PG_NET2,10.10.102.55,10.10.102.1,255.255.255.0,10.0.0.1
.PARAMETER creds
	The username and password for the guest OS of the test VM.
.PARAMETER vmName
	A powered on Windows OS virtual machine with UAC disabled and VMware tools running.
	Note this VM will be vMotioned, network reassigned, and IP address changed by this script!
.EXAMPLE
	./virtualFrogNetworkTester.ps1 -clusterName VirtualFrog1 -dvsName vSwitch1 -isStandard:$true -vmName networktestingFrogVM -csvFile c:\temp\map.csv -resultFile c:\temp\virtualFrogRocks.csv
.NOTES
	Author: Jeff Green; Dario Doerflinger
	Date: July 10, 2015; July 25, 2017
	Original script from https://virtualdatacave.com/2015/07/test-host-networking-for-many-hosts-and-port-groups-vlans/
    Port to Standard Switch requested by VMware Code Community
    Port Author: Dario Doerflinger
    Ported Script published at: https://virtualfrog.wordpress.com/2017/07/26/powercli-testing-your-networks/ 
#>

param
(
	[Parameter(Mandatory=$true)]
	[string]$clusterName,
	[Parameter(Mandatory=$true)]
	[string]$dvsName,
	[Parameter(Mandatory=$true)]
	[boolean]$isStandard,
	[Parameter(Mandatory=$true)]
	[pscredential]$creds,
	[Parameter(Mandatory=$true)]
	[string]$vmName,
	[Parameter(Mandatory=$true)]
	[string]$csvFile,
	[int]$timesToPing = 2,
	[int]$pingReplyCountThreshold = 2,
	[Parameter(Mandatory=$true)]
	[string]$resultFile
)

#Setup

# Configure internal variables
$trustVMInvokeable = $false #this is to speed development only.  Set to false.
$testResults = @()
$testPortGroupName = "VirtualFrog"
$data = import-csv $csvFile
$cluster = get-cluster $clusterName
$vm = get-vm $vmName

if ($isStandard -eq $false) {
    $dvs = get-vdswitch $dvsName
    $originalVMPortGroup = ($vm | get-Networkadapter)[0].networkname
	if ($originalVMPortGroup -eq "") {
		$originalVMPortGroup = ($vm | get-virtualswitch -name $dvsName |get-virtualportgroup)[0]
		write-host -Foregroundcolor:red "Adding a fantasy Name to $originalVMPortGroup"
	}
} else {
    $originalVMPortGroup = ($vm | get-Networkadapter)[0].networkname
    $temporaryVar = ($vm |get-networkadapter)[0].NetworkName
	if ($originalVMPortGroup -eq "") {
		$originalVMPortGroup = ($vm |get-vmhost |get-virtualswitch -name $dvsName |get-virtualportgroup -Standard:$true)[0]
		write-host -Foregroundcolor:red "Adding a fantasy Name to $originalVMPortGroup"
	}
}
#We'll use this later to reset the VM back to its original network location if it's empty for some reason wel'll populate it with the first portgroup






#Test if Invoke-VMScript works
if(-not $trustVMInvokeable) {
	if (-not (Invoke-VMScript -ScriptText "echo test" -VM $vm -GuestCredential $creds).ScriptOutput -eq "test") {
		write-output "Unable to run scripts on test VM guest OS!"
		return 1
	}
}

#Define Test Functions
function TestPing($ip, $count, $mtuTest) {
	if($mtuTest) {
		$count = 4 #Less pings for MTU test
		$pingReplyCountThreshold = 3 #Require 3 responses for success on MTU test.  Note this scope is local to function and will not impact variable for future run.
		$script = "ping -f -l 8972 -n $count $ip"
	} else {
		$script =  "ping -n $count $ip"
	}
	
	write-host -ForegroundColor yellow "Script to run: $script"
	$result = Invoke-VMScript -ScriptText $script -VM $vm -GuestCredential $creds
	
	#parse the output for the "received packets" number
	$rxcount = (( $result.ScriptOutput | Where-Object { $_.indexof("Packets") -gt -1 } ).Split(',') | Where-Object { $_.indexof("Received") -gt -1 }).split('=')[1].trim()
	
	#if we received enough ping replies, consider this a success
	$success = ([int]$rxcount -ge $pingReplyCountThreshold) 
	
	#however there is one condition where this will be a false positive... gateway reachable but destination not responding
	if ( $result.ScriptOutput | Where-Object { $_.indexof("host unreach") -gt -1 } ) {
		$success = $false
		$rxcount = 0;
	}
	
	write-host "Full results of ping test..."
	write-host -ForegroundColor green $result.ScriptOutput
	
	return @($success, $count, $rxcount);
}

function SetGuestIP($ip, $subnet, $gw) {
  $script = @"
  function Elevate-Process  {
	param ([string]`$exe = `$(Throw 'Pleave provide the name and path of an executable'),[string]`$arguments)
	`$startinfo = new-object System.Diagnostics.ProcessStartInfo 
	`$startinfo.FileName = `$exe
	`$startinfo.Arguments = `$arguments 
	`$startinfo.verb = 'RunAs' 
	`$process = [System.Diagnostics.Process]::Start(`$startinfo)
	}
	
	Elevate-Process -Exe C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -Arguments "-noninteractive -command netsh interface ip set address name=((gwmi win32_networkadapter -filter 'netconnectionstatus = 2' | select -First 1).interfaceindex) static $ip $subnet $gw
	netsh interface ipv4 set subinterface ((gwmi win32_networkadapter -filter 'netconnectionstatus = 2' | select -First 1).interfaceindex) mtu=1500 store=active"
"@
  Start-Sleep -Seconds 2
  write-host -ForegroundColor Yellow "Script to run: " $script
  return (Invoke-VMScript -ScriptType Powershell -ScriptText $script -VM $vm -GuestCredential $creds)
}

#Tests
# Per Port Group Tests  (Test each port group)

$vmhost = $vm.vmhost
if ($isStandard -eq $false)
{
	foreach($item in $data) {
		if($testPortGroup = $dvs | get-vdportgroup -name $item.PortGroup) {
			($vm | get-Networkadapter)[0] | Set-NetworkAdapter -Portgroup $testPortGroup -confirm:$false
			if( SetGuestIP $item.SourceIP $item.SubnetMask $item.GatewayIP ) {
				Write-Output ("Set Guest IP to " + $item.SourceIP)
			
				#Run normal ping test
				$pingTestResult = TestPing $item.TestIP $timesToPing $false
				#Add to results
				$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
				$thisTest["Host"] = $vmhost.name
				$thisTest["PortGroupName"] = $testPortGroup.name
				$thisTest["VlanID"] = $testPortGroup.vlanconfiguration.vlanid
				$thisTest["SourceIP"] = $item.SourceIP
				$thisTest["DestinationIP"] = $item.TestIP
				$thisTest["Result"] = $pingTestResult[0].tostring()
				$thisTest["TxCount"] = $pingTestResult[1].tostring()
				$thisTest["RxCount"] = $pingTestResult[2].tostring()
				$thisTest["JumboFramesTest"] = ""
				$thisTest["Uplink"] = $thisUplink

				$testResults += new-object -typename psobject -Property $thisTest

				#DISABLED JUMBO FRAMES TEST!
				if($false) {
					#Run jumbo frames test
					$pingTestResult = TestPing $item.TestIP $timesToPing $true
					#Add to results
					$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
					$thisTest["Host"] = $vmhost.name
					$thisTest["PortGroupName"] = $testPortGroup.name
					$thisTest["VlanID"] = $testPortGroup.vlanconfiguration.vlanid
					$thisTest["SourceIP"] = $item.SourceIP
					$thisTest["DestinationIP"] = $item.TestIP
					$thisTest["Result"] = $pingTestResult[0].tostring()
					$thisTest["TxCount"] = $pingTestResult[1].tostring()
					$thisTest["RxCount"] = $pingTestResult[2].tostring()
					$thisTest["JumboFramesTest"] = ""
					$thisTest["Uplink"] = $thisUplink
					
					$testResults += new-object -typename psobject -Property $thisTest
				}	

			
			} else {
				$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
				$thisTest["PortGroupName"] = $testPortGroup.name
				$thisTest["VlanID"] = $testPortGroup.vlanconfiguration.vlanid
				$thisTest["SourceIP"] = $item.SourceIP
				$thisTest["DestinationIP"] = $item.GatewayIP
				$thisTest["Result"] = "false - error setting guest IP"
				$testResults += new-object -typename psobject -Property $thisTest
			}
		} else {
			$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
			$thisTest["PortGroupName"] = $item.PortGroup
			$thisTest["Result"] = "false - could not find port group"
			$testResults += new-object -typename psobject -Property $thisTest
		}
	}
}
else {
    #This is for a Standard Switch
	foreach($item in $data) {
		$dvs = $vm |get-vmhost | get-virtualswitch -name $dvsName
		if($testPortGroup = $dvs | get-virtualportgroup -name $item.PortGroup) {
			($vm | get-Networkadapter)[0] | Set-NetworkAdapter -Portgroup $testPortGroup -confirm:$false
			if( SetGuestIP $item.SourceIP $item.SubnetMask $item.GatewayIP ) {
				Write-Output ("Set Guest IP to " + $item.SourceIP)
			
				#Run normal ping test
				$pingTestResult = TestPing $item.TestIP $timesToPing $false
				#Add to results
				$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
				$thisTest["Host"] = $vmhost.name
				$thisTest["PortGroupName"] = $testPortGroup.name
				$thisTest["VlanID"] = $testPortGroup.vlanid
				$thisTest["SourceIP"] = $item.SourceIP
				$thisTest["DestinationIP"] = $item.TestIP
				$thisTest["Result"] = $pingTestResult[0].tostring()
				$thisTest["TxCount"] = $pingTestResult[1].tostring()
				$thisTest["RxCount"] = $pingTestResult[2].tostring()
				$thisTest["JumboFramesTest"] = ""
				$thisTest["Uplink"] = $thisUplink

				$testResults += new-object -typename psobject -Property $thisTest

				#DISABLED JUMBO FRAMES TEST!
				if($false) {
					#Run jumbo frames test
					$pingTestResult = TestPing $item.TestIP $timesToPing $true
					#Add to results
					$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
					$thisTest["Host"] = $vmhost.name
					$thisTest["PortGroupName"] = $testPortGroup.name
					$thisTest["VlanID"] = $testPortGroup.vlanid
					$thisTest["SourceIP"] = $item.SourceIP
					$thisTest["DestinationIP"] = $item.TestIP
					$thisTest["Result"] = $pingTestResult[0].tostring()
					$thisTest["TxCount"] = $pingTestResult[1].tostring()
					$thisTest["RxCount"] = $pingTestResult[2].tostring()
					$thisTest["JumboFramesTest"] = ""
					$thisTest["Uplink"] = $thisUplink
					
					$testResults += new-object -typename psobject -Property $thisTest
				}	

			
			} else {
				$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
				$thisTest["PortGroupName"] = $testPortGroup.name
				$thisTest["VlanID"] = $testPortGroup.vlanid
				$thisTest["SourceIP"] = $item.SourceIP
				$thisTest["DestinationIP"] = $item.GatewayIP
				$thisTest["Result"] = "false - error setting guest IP"
				$testResults += new-object -typename psobject -Property $thisTest
			}
		} else {
			$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
			$thisTest["PortGroupName"] = $item.PortGroup
			$thisTest["Result"] = "false - could not find port group"
			$testResults += new-object -typename psobject -Property $thisTest
		}
	}
}


# Per Host Tests (Test Each Link for Each VLAN ID on each host)
$testPortGroup = $null

if ($isStandard -eq $false) 
{

	($testPortGroup = new-vdportgroup $dvs -Name $testPortGroupName -ErrorAction silentlyContinue) -or ($testPortGroup = $dvs | get-vdportgroup -Name $testPortGroupName)
	($vm | get-Networkadapter)[0] | Set-NetworkAdapter -Portgroup $testPortGroup -confirm:$false

	$cluster | get-vmhost | Where-Object {$_.ConnectionState -match "connected" } | ForEach-Object {
		$vmhost = $_
		#Migrate VM to new host
		if(Move-VM -VM $vm -Destination $vmhost) {
	
			foreach($item in $data) {
				#Configure test port group VLAN ID for this particular VLAN test, or clear VLAN ID if none exists
				$myVlanId = $null
				$myVlanId = (get-vdportgroup -name $item.PortGroup).VlanConfiguration.Vlanid
				if($myVlanId) {
					$testPortGroup = $testPortGroup | Set-VDVlanConfiguration -Vlanid $myVlanId
				} else {
					$testPortGroup = $testPortGroup | Set-VDVlanConfiguration -DisableVlan
				}
			
			
				if( SetGuestIP $item.SourceIP $item.SubnetMask $item.GatewayIP ) {
					Write-Output ("Set Guest IP to " + $item.SourceIP)
				
					#Run test on each uplink individually
					$uplinkset = ( ($testPortGroup | Get-VDUplinkTeamingPolicy).ActiveUplinkPort + ($testPortGroup | Get-VDUplinkTeamingPolicy).StandbyUplinkPort ) | sort
					foreach($thisUplink in $uplinkset) {
						#Disable all uplinks from the test portgroup
						$testPortGroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -UnusedUplinkPort $uplinkset
						#Enable  only this uplink for the test portgroup
						$testPortGroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort $thisUplink

						#Run normal ping test
						$pingTestResult = TestPing $item.TestIP $timesToPing $false
						#Add to results
						$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
						$thisTest["Host"] = $vmhost.name
						$thisTest["PortGroupName"] = $testPortGroup.name
						$thisTest["VlanID"] = $testPortGroup.vlanconfiguration.vlanid
						$thisTest["SourceIP"] = $item.SourceIP
						$thisTest["DestinationIP"] = $item.TestIP
						$thisTest["Result"] = $pingTestResult[0].tostring()
						$thisTest["TxCount"] = $pingTestResult[1].tostring()
						$thisTest["RxCount"] = $pingTestResult[2].tostring()
						$thisTest["JumboFramesTest"] = ""
						$thisTest["Uplink"] = $thisUplink

						$testResults += new-object -typename psobject -Property $thisTest

						#DISABLED JUMBO FRAMES TEST!
						if($false) {
							#Run jumbo frames test
							$pingTestResult = TestPing $item.TestIP $timesToPing $true
							#Add to results
							$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
							$thisTest["Host"] = $vmhost.name
							$thisTest["PortGroupName"] = $testPortGroup.name
							$thisTest["VlanID"] = $testPortGroup.vlanconfiguration.vlanid
							$thisTest["SourceIP"] = $item.SourceIP
							$thisTest["DestinationIP"] = $item.TestIP
							$thisTest["Result"] = $pingTestResult[0].tostring()
							$thisTest["TxCount"] = $pingTestResult[1].tostring()
							$thisTest["RxCount"] = $pingTestResult[2].tostring()
							$thisTest["JumboFramesTest"] = ""
							$thisTest["Uplink"] = $thisUplink
							
							$testResults += new-object -typename psobject -Property $thisTest
						}					
					}
				
					$testPortGroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort ($uplinkset | sort)
				
				} else {
					$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
					$thisTest["PortGroupName"] = $testPortGroup.name
					$thisTest["VlanID"] = $testPortGroup.vlanconfiguration.vlanid
					$thisTest["SourceIP"] = $item.SourceIP
					$thisTest["DestinationIP"] = $item.GatewayIP
					$thisTest["Result"] = "false - error setting guest IP"
					$testResults += new-object -typename psobject -Property $thisTest
				}
			}
		} else {
			$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
			$thisTest["Result"] = "false - unable to vMotion VM to this host"
			$testResults += new-object -typename psobject -Property $thisTest
		}
	}
}
else {
    #This is for a standard Switch
    $vmhost = $null

    #adding the testPortGroup on all hosts in the cluster
    $cluster | get-vmhost | Where-Object {$_.ConnectionState -match "connected" } | sort | ForEach-Object {
		$dvs = get-virtualswitch -Name $dvsName -VMhost $_
    	$dvs | new-virtualportgroup -Name $testPortGroupName -ErrorAction silentlyContinue
    }

    $vmhost = $null
	$cluster | get-vmhost | Where-Object {$_.ConnectionState -match "connected" } | sort | ForEach-Object {
		$vmhost = $_
		$dvs = get-virtualswitch -Name $dvsName -VMhost $vmhost
		$testPortGroup = $dvs |get-virtualportgroup -Name $testPortGroupName -VMhost $vmhost -ErrorAction silentlyContinue


		#Migrate VM to new host
		if(Move-VM -VM $vm -Destination $vmhost) {
				write-host -Foregroundcolor:red "Sleeping 5 seconds..."
				start-sleep -seconds 5
				if (($vm | get-Networkadapter)[0] | Set-NetworkAdapter -Portgroup ($dvs |get-virtualportgroup -Name $testPortGroupName -VMhost $vmhost) -confirm:$false -ErrorAction stop)
				{
					write-host -Foregroundcolor:green "Adapter Change successful"
				}else {
				    write-host -Foregroundcolor:red "Cannot change adapter!"
				    #$esxihost = $vm |get-vmhost
				    #$newPortgroup = $esxihost | get-virtualportgroup -Name testPortGroupName -ErrorAction silentlyContinue
				    #if (($vm | get-Networkadapter)[0] | Set-NetworkAdapter -Portgroup ($newPortgroup) -confirm:$false -ErrorAction stop) {
				    #    write-host -Foregroundcolor:green "Adapter Change successful (2nd attempt)"
				    #} else {
				    #    write-host -Foregroundcolor:red "Cannot change Adapter even on 2nd attempt. Exiting script"
				    #    exit 1
				    #}
				}

			
	
			foreach($item in $data) {
				#Configure test port group VLAN ID for this particular VLAN test, or clear VLAN ID if none exists
				$myVlanId = $null
				$myVlanId = [int32](get-virtualportgroup -VMhost $vmhost -Standard:$true -name $item.PortGroup).Vlanid
				if($myVlanId) {
					$testPortGroup = $testPortGroup | Set-VirtualPortGroup -Vlanid $myVlanId
				} else {
					$testPortGroup = $testPortGroup | Set-VirtualPortGroup -VlanId 0
				}
			
			
				if( SetGuestIP $item.SourceIP $item.SubnetMask $item.GatewayIP ) {
					Write-Output ("Set Guest IP to " + $item.SourceIP)
				
					#Run test on each uplink individually
					$uplinkset = ( ($testPortGroup | Get-NicTeamingPolicy).ActiveNic + ($testPortGroup |Get-NicTeamingPolicy).StandbyNic ) |sort
					foreach($thisUplink in $uplinkset) {
						#Disable all uplinks from the test portgroup
						$testPortGroup | Get-NicTeamingPolicy | Set-NicTeamingPolicy -MakeNicUnused $uplinkset
						#Enable  only this uplink for the test portgroup
						$testPortGroup | Get-NicTeamingPolicy | Set-NicTeamingPolicy -MakeNicActive $thisUplink

						#Run normal ping test
						$pingTestResult = TestPing $item.TestIP $timesToPing $false
						#Add to results
						$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
						$thisTest["Host"] = $vmhost.name
						$thisTest["PortGroupName"] = $testPortGroup.name
						$thisTest["VlanID"] = $testPortGroup.vlanid
						$thisTest["SourceIP"] = $item.SourceIP
						$thisTest["DestinationIP"] = $item.TestIP
						$thisTest["Result"] = $pingTestResult[0].tostring()
						$thisTest["TxCount"] = $pingTestResult[1].tostring()
						$thisTest["RxCount"] = $pingTestResult[2].tostring()
						$thisTest["JumboFramesTest"] = ""
						$thisTest["Uplink"] = $thisUplink

						$testResults += new-object -typename psobject -Property $thisTest

						#DISABLED JUMBO FRAMES TEST!
						if($false) {
							#Run jumbo frames test
							$pingTestResult = TestPing $item.TestIP $timesToPing $true
							#Add to results
							$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
							$thisTest["Host"] = $vmhost.name
							$thisTest["PortGroupName"] = $testPortGroup.name
							$thisTest["VlanID"] = $testPortGroup.vlanid
							$thisTest["SourceIP"] = $item.SourceIP
							$thisTest["DestinationIP"] = $item.TestIP
							$thisTest["Result"] = $pingTestResult[0].tostring()
							$thisTest["TxCount"] = $pingTestResult[1].tostring()
							$thisTest["RxCount"] = $pingTestResult[2].tostring()
							$thisTest["JumboFramesTest"] = ""
							$thisTest["Uplink"] = $thisUplink
							
							$testResults += new-object -typename psobject -Property $thisTest
						}					
					}
				
					$testPortGroup | Get-NicTeamingPolicy | Set-NicTeamingPolicy -MakeNicActive ($uplinkset | sort)
				
				} else {
					$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
					$thisTest["PortGroupName"] = $testPortGroup.name
					$thisTest["VlanID"] = $testPortGroup.vlanid
					$thisTest["SourceIP"] = $item.SourceIP
					$thisTest["DestinationIP"] = $item.GatewayIP
					$thisTest["Result"] = "false - error setting guest IP"
					$testResults += new-object -typename psobject -Property $thisTest
				}
			}
		} else {
			$thisTest = [ordered]@{"VM" = $vm.name; "TimeStamp" = (Get-Date -f s); "Host" = $vmhost.name;}
			$thisTest["Result"] = "false - unable to vMotion VM to this host"
			$testResults += new-object -typename psobject -Property $thisTest
		}
	}
}

#Clean up
if ($isStandard -eq $false)
{
	($vm | get-Networkadapter)[0] | Set-NetworkAdapter -Portgroup (get-vdportgroup $originalVMPortGroup) -confirm:$false
	Remove-VDPortGroup -VDPortGroup $testPortGroup -confirm:$false

} else {
	$tempvm = get-vm $vmName
	$temphost = $tempvm |get-VMhost
	$portGroupToRevertTo = $temphost |get-virtualportgroup -name $temporaryVar -Standard:$true
    ($vm | get-Networkadapter)[0] | Set-NetworkAdapter -Portgroup $portGroupToRevertTo -confirm:$false
    write-host -Foregroundcolor:green "Waiting 5 seconds for $vm to revert back to $temporaryVar"
    start-sleep -seconds 5
    $cluster | get-vmhost | Where-Object {$_.ConnectionState -match "connected" } | ForEach-Object {
		$vmhost = $_
		$dvs = $vmhost | get-virtualswitch -Name $dvsName
		$testPortGroup = $dvs | get-virtualportgroup -name $testPortGroupName -Standard:$true -VMhost $vmhost
		remove-virtualportgroup -virtualportgroup $testPortGroup -confirm:$false
	}
}

#Future Test Ideas
#Query driver/firmware for each host's network adapters ?

#Show Results
$testResults | Format-Table
$testResults | Export-CSV -notypeinformation $resultFile
