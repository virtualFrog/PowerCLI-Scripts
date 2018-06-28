$clusters = get-cluster
$myClusters = @()
foreach ($cluster in $clusters) {
    $hosts = $cluster |get-vmhost
 
    [double]$cpuAverage = 0
    [double]$memAverage = 0
 
    Write-Host $cluster
    foreach ($esx in $hosts) {
        Write-Host $esx
        [double]$esxiCPUavg = [double]($esx | Select-Object @{N = 'cpuAvg'; E = {[double]([math]::Round(($_.CpuUsageMhz) / ($_.CpuTotalMhz) * 100, 2))}} |Select-Object -ExpandProperty cpuAvg)
        $cpuAverage = $cpuAverage + $esxiCPUavg
 
        [double]$esxiMEMavg = [double]($esx | Select-Object @{N = 'memAvg'; E = {[double]([math]::Round(($_.MemoryUsageMB) / ($_.MemoryTotalMB) * 100, 2))}} |select-object -ExpandProperty memAvg)
        $memAverage = $memAverage + $esxiMEMavg
    }
    $cpuAverage = [math]::Round(($cpuAverage / ($hosts.count) ), 1)
    $memAverage = [math]::Round(($memAverage / ($hosts.count) ), 1)
    $ClusterInfo = "" | Select-Object Name, CPUAvg, MEMAvg
    $ClusterInfo.Name = $cluster.Name
    $ClusterInfo.CPUAvg = $cpuAverage
    $ClusterInfo.MEMAvg = $memAverage
    $myClusters += $ClusterInfo
}
$myClusters