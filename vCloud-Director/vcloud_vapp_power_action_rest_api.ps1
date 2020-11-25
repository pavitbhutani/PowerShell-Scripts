# Author: Pavit Bhutani.
# Script powers on/off all vApps in specified Org.
# Specify 'system' as Org if you want to perform this on all Orgs.

# Script variables.
$vcloudHost = ""
$vcloudOrg = ""
$vcloudUserName = ""
$vcloudPassword = ""
$vcloudApiVersion = ""
# Specify powerAction as 'on' or 'off'.
$powerAction = "on"

# Login to vCloud Director using REST API.
function Login-Vcloud {
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$Vcloud,
        [Parameter(Mandatory=$true)]
        [string]$OrgName,
        [Parameter(Mandatory=$true)]
        [string]$UserName,
        [Parameter(Mandatory=$true)]
        [string]$Password
    )
    $vcdAuth = $UserName + '@' + $OrgName + ':' + $Password
    $vcdEncoded = [System.Text.Encoding]::UTF8.GetBytes($vcdAuth)
    $vcdEncodedPassword = [System.Convert]::ToBase64String($vcdEncoded)
    $headers = @{"Accept"="application/*+xml;version=$vcloudApiVersion"}
    $vcdBaseUrl = "https://$Vcloud/api"

    $vcdLoginUrl = $vcdBaseUrl + "/sessions"
    $headers += @{"Authorization"="Basic $($vcdEncodedPassword)"}
    $vcdResponse = Invoke-WebRequest -Uri $vcdLoginUrl -Headers $headers -Method POST -UseBasicParsing
    if ($vcdResponse.StatusCode -eq "200") {
        $token = $vcdResponse.Headers.'x-vcloud-authorization'
        $headers.Add("x-vcloud-authorization", "$token")
        return $headers
    }
}

# Perform power action on all vApps.
function PowerAction-AllVapps {
    Param
    (   [Parameter(Mandatory=$true)]
        [string]$Vcloud,
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers,
        [Parameter(Mandatory=$true)]
        [string]$PowerAction,
        [Parameter(Mandatory=$false)]
        [switch]$RunAsync
    )
    
    [int32]$pageSize = 128
    $vappsLookupUrl = "https://" + $Vcloud + "/api/query?type=vApp&format=records&pageSize=$pageSize"
    $vapps = (Invoke-RestMethod -Uri $vappsLookupUrl -Method Get -Headers $Headers).QueryResultRecords

    if ($PowerAction -like "*on") {
        $vappPowerAction = "/power/action/powerOn"
    } elseif ($PowerAction -like "*off") {
        $vappPowerAction = "/power/action/powerOff"
    }

    $vappsPageCount = [math]::Ceiling($vapps.total/$pageSize)
    [Int32]$p = 1
    do {
        [Int32]$i = 1
        $vappsPageLookupUrl = $vappsLookupUrl + "&page=$p"
        $vappsPage = Invoke-RestMethod -Uri $vappsPageLookupUrl -Method Get -Headers $Headers
        foreach ($vappPage in $vappsPage.QueryResultRecords.VAppRecord) {
            Write-Host ""
            Write-Host "Checking vApp $($vappPage.name), $i of $($vapps.total)." -ForegroundColor Green
            $vappPowerActionUrl = $vappPage.href + $vappPowerAction
            try {
                $vappPowerActionResponse = Invoke-RestMethod -Uri $vappPowerActionUrl -Method Post -Headers $Headers
                Write-Host "Power action initiated." -ForegroundColor Green
            } catch {
                $_.Exception.Message
            }
            
            if ($RunAsync -eq $true) {
                ## Waiting 5 seconds to ensure vCD's task table isn't overwhelmed with power action tasks.
                Start-Sleep -Seconds 5
            } else {
                if ($vappPowerActionResponse) {
                    $vappPowerActionResponseTaskStartTime = Get-Date
                    $vappPowerActionResponseTask = $vappPowerActionResponse.Task.href
                    $vappPowerActionResponseTaskStatus = Invoke-RestMethod -Uri $vappPowerActionResponseTask -Method Get -Headers $Headers
                    $vappPowerActionResponseTaskCheckTime = Get-Date
                    $vappPowerActionResponseTaskTimeElapsed = (New-TimeSpan –Start $vappPowerActionResponseTaskStartTime –End $vappPowerActionResponseTaskCheckTime).TotalMinutes
                    while ($vappPowerActionResponseTaskStatus.Task.status -notlike "success" -and $vappPowerActionResponseTaskTimeElapsed -lt 5) {
                        $vappPowerActionResponseTaskStatus = Invoke-RestMethod -Uri $vappPowerActionResponseTask -Method Get -Headers $Headers
                        Write-Host "Power action in progress, invoking wait for 5 seconds."
                        Start-Sleep -Seconds 5
                        $vappPowerActionResponseTaskCheckTime = Get-Date
                        $vappPowerActionResponseTaskTimeElapsed = (New-TimeSpan –Start $vappPowerActionResponseTaskStartTime –End $vappPowerActionResponseTaskCheckTime).TotalMinutes
                    }
                    Write-Host "Power action completed for vApp $($vappPage.name)." -ForegroundColor Green
                    Clear-Variable vappPowerActionResponse
                }
            }
            $i++
        }
        $p++
    }
    while ($p -le $vappsPageCount)
}

$vcdHeaders = Login-Vcloud -Vcloud $vcloudHost -OrgName $vcloudOrg -UserName $vcloudUserName -Password $vcloudPassword
if ($vcdHeaders) {
    Write-Host "Logged in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Green
    PowerAction-AllVapps -Vcloud $vcloudHost -PowerAction $powerAction -Headers $vcdHeaders -RunAsync
} else {
    Write-Host "Failed to log in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Red
}