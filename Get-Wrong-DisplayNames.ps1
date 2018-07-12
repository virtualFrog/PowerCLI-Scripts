$OutArray = @()

$vms = Get-VM
foreach ($vm in $vms)
{
    $myobj = "" | Select "VM", "DNSname", "Status"
    $guest = Get-VMGuest -VM $vm
    $pat = "."
    $vmname = $guest.VmName
    $hostname = $guest.HostName
    $myobj.VM = $vmname
    $myobj.DNSname = $hostname
    if ( $hostname -ne $null)
    {
        $pos = $hostname.IndexOf(".")
        if ( $pos -ne "-1")
        {
            $hostname = $hostname.Substring(0, $pos)
        }
        if ( $hostname -ne $vmname )
        {
            Write-Host -ForegroundColor Red "---> The VM: $vm has different DNS and Display-Name!"
            Write-Host -ForegroundColor Red "---->Hostname: " $hostname
            Write-Host -ForegroundColor Red "---->VmName: "$vmname
            $myobj.Status = "Not OK!"
        }
        Else
        {
            Write-Host -ForegroundColor Green "---> The VM: $vm has identical Names."
            $myobj.Status = "OK!"
        }
    }
    Else
    {
        Write-Host -ForegroundColor Yellow "---> The VM: $vm is not powered-on. Hostname cannot be found in this state!"
        $myobj.Status = "N/A"
    }
    Clear-variable -Name hostname
    Clear-variable -Name vmname
    $OutArray += $myobj
}
$OutArray | Export-Csv "c:\tmp\name_vs_dns_$vcenter.csv"