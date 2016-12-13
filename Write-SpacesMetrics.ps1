# Set InfluxDB API URI
$uri = 'http://grafanauri:8086/write?db=IgniteS2D'

# Set the reporting collection interval for 1 second
Get-StorageSubSystem -FriendlyName clus* | Set-StorageHealthSetting -Name 'System.Reports.ReportingPeriodSeconds' -Value 1

# Loop for one hour
$timeout   = New-TimeSpan -Hours 1
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

while ($stopwatch.elapsed -lt $timeout)
{
    ### Health Services Cluster Report
    # Get the storage health report
    $report = Get-StorageSubSystem -FriendlyName clus* | Get-StorageHealthReport -Count 1

    # Loop through every attribute and write it to the database
    foreach ( $r in $($report).ItemValue.Records )
    {
        Invoke-WebRequest -Method Post -Body ('{0} value={1}' -f $r.Name, $r.Value) -Uri $uri
    }

    ### Storage QOS
    $qos = Get-StorageQoSVolume

    foreach ($q in $qos)
    {
        $hostname = $(($q.Mountpoint).Split('\')[-2])

        if ($hostname -ne 'Collect')
        {
            Invoke-WebRequest -Method Post -Body ('VolumeLatency,host={0} value={1}' -f $hostname, $q.Latency) -Uri $uri
        }
    }

    # Wait 5 seconds before iterating
    Start-Sleep -Seconds 5
}