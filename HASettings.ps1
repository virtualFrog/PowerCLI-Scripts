# Parameters
$VMServer = ‘vCenterFQDN’
$OutFile = ‘C:\Path\To\File.csv’
 
# Connect to vCenter and get HA settings for every cluster
Connect-VIServer -Server $VMServer -ErrorAction Stop | Out-Null
Get-Cluster | Select-Object Name, HAAdmissionControlEnabled,
@{N = 'Host failures cluster tolerates'; E = {$_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.FailOverLevel}},
@{N = 'Define host failover capacity by'; E = {
        switch ($_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.GetTYpe().Name) {
            'ClusterFailoverHostAdmissionControlPolicy' {'Dedicated Failover Hosts (H)'}
            'ClusterFailoverResourcesAdmissionControlPolicy' {'Cluster Resource Percentage (R)'}
            'ClusterFailoverLevelAdmissionControlPolicy' {'Slot Policy (s)'}
        }}
},
@{N = '(H) Failover Hosts '; E = {(Get-View -Id $_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.FailOverHosts -Property Name).Name -join '|'}},
@{N = '(R) Override calculated failover capacity'; E = {
        if ($_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.AutoComputePercentages) {'True'}
        else {'False (R-O)'}}
},
@{N = '(R-O) CPU %'; E = {$_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.CpuFailoverResourcesPercent}},
@{N = '(R-O) Memory %'; E = {$_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.MemoryFailoverResourcesPercent}},
@{N = '(S) Slot Policy '; E = {
        if ($_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.SlotPolicy) {'Fixed Slot Size (S-F)'}
        else {'Cover all powered-on VM'}
    }
},
@{N = '(S-F) CPU MhZ'; E = {$_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.SlotPolicy.Cpu}},
@{N = '(S-F) Memory MB'; E = {$_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.SlotPolicy.Memory}},
@{N = 'HA Admission Policy ResourceReductionToToleratePercent'; E = {$_.ExtensionData.Configuration.DasConfig.AdmissionControlPolicy.ResourceReductionToToleratePercent}},
@{N = 'Hearthbeat Datastore Policy'; E = {
        switch ($_.ExtensionData.Configuration.DasConfig.HBDatastoreCandidatePolicy) {
            'allFeasibleDs' {'Automatically select datastores accessible from the host'}
            'allFeasibleDsWithUserPreference' {'Use datastores from the specified list and complement automatically (L)'}
            'userSelectedDs' {'Use datastores only from the specified list (L)'}
        }
    }
},
@{N = '(L) Hearthbeat Datastore'; E = {(Get-View -Id $_.ExtensionData.Configuration.DasConfig.HeartbeatDatastore -property Name).Name -join '|'}},
@{N = 'Host Monitoring'; E = {$_.ExtensionData.Configuration.DasConfig.HostMonitoring}},
@{N = 'Host Failure Response'; E = {
        if ($_.ExtensionData.Configuration.DasConfig.DefaultVmSettings.RestartPriority -eq 'disabled') {'Disabled'}
        else {'Restart VMs'}}
},
@{N = 'Host Isolation Response'; E = {$_.ExtensionData.Configuration.DasConfig.DefaultVmSettings.IsolationResponse}},
@{N = 'Datastore with PDL'; E = {$_.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmStorageProtectionForPDL}},
@{N = 'Datastore with APD'; E = {$_.ExtensionData.Configuration.DasConfig.DefaultVmSettings.VmComponentProtectionSettings.VmStorageProtectionForAPD}},
@{N = 'VM Monitoring'; E = {$_.ExtensionData.Configuration.DasConfig.VmMonitoring}} | Export-Csv -NoTypeInformation -Path $OutFile
Disconnect-VIServer -Server $VMServer -Confirm:$false -ErrorAction Stop | Out-Null
