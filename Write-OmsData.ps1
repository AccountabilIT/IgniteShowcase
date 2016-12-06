### General Configuration
###

# Replace with your Workspace ID
$CustomerId = 'XXXXXXXXXXXXXXXXXXX'

# Replace with your Primary Key
$SharedKey = 'XXXXXXXXXXXXXXXXXXXXXXXXXX'

# Specify a time in the format YYYY-MM-DDThh:mm:ssZ to specify a created time for the records
$TimeStampField = ''


### Functions
###

# Create the function to create the authorization signature
function New-Signature
{
    param
    (
        $customerId,
        $sharedKey,
        $date,
        $contentLength,
        $method,
        $contentType,
        $resource
    )

    $xHeaders = 'x-ms-date:' + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object -TypeName System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}

# Create the function to create and post the request
function Write-OmsData
{
    param
    (
        $customerId,
        $sharedKey,
        $body,
        $logType
    )

    $method = 'POST'
    $contentType = 'application/json'
    $resource = '/api/logs'
    $rfc1123date = [DateTime]::UtcNow.ToString('r')
    $contentLength = $body.Length
    $signature = New-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -fileName $fileName `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = 'https://' + $customerId + '.ods.opinsights.azure.com' + $resource + '?api-version=2016-04-01'

    $headers = @{
        'Authorization' = $signature;
        'Log-Type' = $logType;
        'x-ms-date' = $rfc1123date;
        'time-generated-field' = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}


### Operations
###

### Health Service Faults
$faults = Get-StorageSubSystem -FriendlyName clus* | Debug-StorageSubSystem

foreach ($fault in $faults)
{

    $faultJson = (@'
    [{{  "FaultSeverity": "{0}",
        "FaultReason": "{1}",
        "FaultDescription": "{2}",
        "FaultReccomendation": "{3}",
        "FaultLocation": "{4}",

    }}]
'@ -f $fault.PerceivedSeverity, $fault.Reason, $fault.FaultingObjectDescription, $fault.RecommendedActions, $fault.FaultingObjectLocation)

    Write-OMSData -customerId $customerId -sharedKey $sharedKey -body ([Text.Encoding]::UTF8.GetBytes($faultJson)) -logType 'SpacesFaults'
}


### Storage QOS
$qos = Get-StorageQoSVolume

foreach ($q in $qos)
{
    $hostname = $(($q.Mountpoint).Split('\')[-2])

    if ($hostname -ne 'Collect')
    {        
        $qosJson = (@'
        [{{  
            "Hostname": "{0}",
            "NumberValue": {1},
            "Status": "{2}"
        }}]
'@ -f $hostname, $q.Latency, $q.Status)

        Write-Output -InputObject $qosJson
        
        Write-OMSData -customerId $customerId -sharedKey $sharedKey -body ([Text.Encoding]::UTF8.GetBytes($qosJson)) -logType 'VolumeLatencyTest'
    }
}