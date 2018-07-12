# import vmware related modules, get the credentials and connect to the vCenter server 
Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null
#$creds = Get-VICredentialStoreItem -file  "D:\Scripts\CreateSnapshotCreationOverview\login.creds"
#Connect-VIServer -Server $creds.Host -User $creds.User -Password $creds.Password
connect-viserver vCenter.virtualfrog.lab

function Get-TaskPlus {
 
<#  
.SYNOPSIS  Returns vSphere Task information   
.DESCRIPTION The function will return vSphere task info. The
  available parameters allow server-side filtering of the
  results
.NOTES  Author:  Luc Dekens  
.PARAMETER Alarm
  When specified the function returns tasks triggered by
  specified alarm
.PARAMETER Entity
  When specified the function returns tasks for the
  specific vSphere entity
.PARAMETER Recurse
  Is used with the Entity. The function returns tasks
  for the Entity and all it's children
.PARAMETER State
  Specify the State of the tasks to be returned. Valid
  values are: error, queued, running and success
.PARAMETER Start
  The start date of the tasks to retrieve
.PARAMETER Finish
  The end date of the tasks to retrieve.
.PARAMETER UserName
  Only return tasks that were started by a specific user
.PARAMETER MaxSamples
  Specify the maximum number of tasks to return
.PARAMETER Reverse
  When true, the tasks are returned newest to oldest. The
  default is oldest to newest
.PARAMETER Server
  The vCenter instance(s) for which the tasks should
  be returned
.PARAMETER Realtime
  A switch, when true the most recent tasks are also returned.
.PARAMETER Details
  A switch, when true more task details are returned
.PARAMETER Keys
  A switch, when true all the keys are returned
.EXAMPLE
  PS> Get-TaskPlus -Start (Get-Date).AddDays(-1)
.EXAMPLE
  PS> Get-TaskPlus -Alarm $alarm -Details
#>
  
  param(
    [CmdletBinding()]
    [VMware.VimAutomation.ViCore.Impl.V1.Alarm.AlarmDefinitionImpl]$Alarm,
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl]$Entity,
    [switch]$Recurse = $false,
    [VMware.Vim.TaskInfoState[]]$State,
    [DateTime]$Start,
    [DateTime]$Finish,
    [string]$UserName,
    [int]$MaxSamples = 100,
    [switch]$Reverse = $true,
    [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl[]]$Server = $global:DefaultVIServer,
    [switch]$Realtime,
    [switch]$Details,
    [switch]$Keys,
    [int]$WindowSize = 100
  )
 
  begin {
    function Get-TaskDetails {
      param(
        [VMware.Vim.TaskInfo[]]$Tasks
      )
      begin{
        $psV3 = $PSversionTable.PSVersion.Major -ge 3
      }
 
      process{
        $tasks | %{
          if($psV3){
            $object = [ordered]@{}
          }
          else {
            $object = @{}
          }
          $object.Add("Name",$_.Name)
          $object.Add("Description",$_.Description.Message)
          if($Details){$object.Add("DescriptionId",$_.DescriptionId)}
          if($Details){$object.Add("Task Created",$_.QueueTime.tolocaltime())}
          $object.Add("Task Started",$_.StartTime.tolocaltime())
          if($Details){$object.Add("Task Ended",$_.CompleteTime.tolocaltime())}
          $object.Add("State",$_.State)
          $object.Add("Result",$_.Result)
          $object.Add("Entity",$_.EntityName)
          $object.Add("VIServer",$VIObject.Name)
          $object.Add("Error",$_.Error.ocalizedMessage)
          if($Details){
            $object.Add("Cancelled",(&{if($_.Cancelled){"Y"}else{"N"}}))
            $object.Add("Reason",$_.Reason.GetType().Name.Replace("TaskReason",""))
            $object.Add("AlarmName",$_.Reason.AlarmName)
            $object.Add("AlarmEntity",$_.Reason.EntityName)
            $object.Add("ScheduleName",$_.Reason.Name)
            $object.Add("User",$_.Reason.UserName)
          }
          if($keys){
            $object.Add("Key",$_.Key)
            $object.Add("ParentKey",$_.ParentTaskKey)
            $object.Add("RootKey",$_.RootTaskKey)
          }
 
          New-Object PSObject -Property $object
        }
      }
    }
 
    $filter = New-Object VMware.Vim.TaskFilterSpec
    if($Alarm){
      $filter.Alarm = $Alarm.ExtensionData.MoRef
    }
    if($Entity){
      $filter.Entity = New-Object VMware.Vim.TaskFilterSpecByEntity
      $filter.Entity.entity = $Entity.ExtensionData.MoRef
      if($Recurse){
        $filter.Entity.Recursion = [VMware.Vim.TaskFilterSpecRecursionOption]::all
      }
      else{
        $filter.Entity.Recursion = [VMware.Vim.TaskFilterSpecRecursionOption]::self
      }
    }
    if($State){
      $filter.State = $State
    }
    if($Start -or $Finish){
      $filter.Time = New-Object VMware.Vim.TaskFilterSpecByTime
      $filter.Time.beginTime = $Start
      $filter.Time.endTime = $Finish
      $filter.Time.timeType = [vmware.vim.taskfilterspectimeoption]::startedTime
    }
    if($UserName){
      $userNameFilterSpec = New-Object VMware.Vim.TaskFilterSpecByUserName
      $userNameFilterSpec.UserList = $UserName
      $filter.UserName = $userNameFilterSpec
    }
    $nrTasks = 0
  }
 
  process {
    foreach($viObject in $Server){
      $si = Get-View ServiceInstance -Server $viObject
      $tskMgr = Get-View $si.Content.TaskManager -Server $viObject 
 
      if($Realtime -and $tskMgr.recentTask){
        $tasks = Get-View $tskMgr.recentTask
        $selectNr = [Math]::Min($tasks.Count,$MaxSamples-$nrTasks)
        Get-TaskDetails -Tasks[0..($selectNr-1)]
        $nrTasks += $selectNr
      }
 
      try {
      $tCollector = Get-View ($tskMgr.CreateCollectorForTasks($filter))
 
      if($Reverse){
        $tCollector.ResetCollector()
        $taskReadOp = $tCollector.ReadPreviousTasks
      }
      else{
        $taskReadOp = $tCollector.ReadNextTasks
      }
      do{
        $tasks = $taskReadOp.Invoke($WindowSize)
        if(!$tasks){return}
        $selectNr = [Math]::Min($tasks.Count,$MaxSamples-$nrTasks)
        Get-TaskDetails -Tasks $tasks[0..($selectNr-1)]
        $nrTasks += $selectNr
      }while($nrTasks -lt $MaxSamples)
      }
      catch {
        Write-Host "A error occured in the collector"
      }
    }
    try {
        $tCollector.DestroyCollector()
        }
    catch {
        Write-Host "The error not letting us destroy the collector"
    }
  }
}
$start = (Get-Date).AddDays(-30)
$finish = (Get-Date)
$output = Get-TaskPlus -Details -MaxSamples 20000000 -Start $start -Finish $finish | ? {$_.Name -match "CreateSnapshot_Task" -or $_.Name -match "RemoveSnapshot_Task"} |select Entity, "Task Created", "Task Started", "Task Ended", User, State, Name, @{Name="Duration in Seconds"; Expression = {(New-TimeSpan -start $_."Task Started" -End $_."Task Ended").TotalSeconds}}
# create a CSV file with all snapshot related results
$output | Export-Csv -Path "c:\temp\snapshot_create_and_remove_times_last_month.csv" -NoTypeInformation

# cleanup and removal of loaded VMware modules
#Disconnect-VIServer -Server $creds.Host -Confirm:$false
disconnect-viserver vCenter.virtualfrog.lab -confirm:$false
Remove-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue | Out-Null
