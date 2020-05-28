# Author: Pavit Bhutani.
# Script renews lease of all or specified vApps (including expired ones) in the Org.
# Specify vApps to renew in the vappsToRenew variable as 'ALL' for all vApps.
# Or use wildcards in the vappsToRenew variable for vApp name like prod* or *dev* etc.
# Specify 0 in deploymentLeaseDays and storageLeaseDays to set permanent lease.

# Script variables.
$vcloudHost = ""
$vcloudOrg = ""
$vcloudUserName = ""
$vcloudPassword = ""
$vcloudApiVersion = ""
$vappsToRenew = ""
$deploymentLeaseDays = ""
$storageLeaseDays = ""

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

# Copy content from source to destination catalog.
function Renew-VappLease {
    Param
    (   [Parameter(Mandatory=$true)]
        [string]$Vcloud,
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers,
        [Parameter(Mandatory=$true)]
        [string]$VappsToRenew,
        [Parameter(Mandatory=$true)]
        [string]$DeploymentLeaseDays,
        [Parameter(Mandatory=$true)]
        [string]$StorageLeaseDays
    )
    [int32]$pageSize = 128
    if ($VappsToRenew -eq "ALL") {
        $vappsLookupUrl = "https://" + $Vcloud + "/api/query?type=vApp&format=records&pageSize=$pageSize"
    } else {
        $vappsLookupUrl = "https://" + $Vcloud + "/api/query?type=vApp&format=records&pageSize=$pageSize&filter=(name==$VappsToRenew)"
    }
    $vapps = (Invoke-RestMethod -Uri $vappsLookupUrl -Method Get -Headers $Headers).QueryResultRecords
    
    $vappLeaseRenewContentType = "application/vnd.vmware.vcloud.leaseSettingsSection+xml"
    $vappLeaseRenewBody = 
    @"
    <LeaseSettingsSection
    xmlns="http://www.vmware.com/vcloud/v1.5"
    xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
    type="application/vnd.vmware.vcloud.leaseSettingsSection+xml">
    <ovf:Info>Lease Settings</ovf:Info>
    <DeploymentLeaseInSeconds>$($DeploymentLeaseDays*24*60*60)</DeploymentLeaseInSeconds>
    <StorageLeaseInSeconds>$($StorageLeaseDays*24*60*60)</StorageLeaseInSeconds>
    </LeaseSettingsSection>
"@

    $vappsPageCount = [math]::Ceiling($vapps.total/$pageSize)
    [Int32]$p = 1
    do {
        [Int32]$i = 1
        $vappsPageLookupUrl = $vappsLookupUrl + "&page=$p"
        $vappsPage = Invoke-RestMethod -Uri $vappsPageLookupUrl -Method Get -Headers $Headers
        foreach ($vappPage in $vappsPage.QueryResultRecords.VAppRecord) {
            Write-Host "Checking vApp $($vappPage.name), $i of $($vapps.total)." -ForegroundColor Green
            $vappPageLeaseRenewUrl = $vappPage.href + "/leaseSettingsSection"
            $vappLeaseRenewResponseTaskStartTime = Get-Date
            $vappLeaseRenewResponse = Invoke-RestMethod -Uri $vappPageLeaseRenewUrl -ContentType $vappLeaseRenewContentType -Body $vappLeaseRenewBody -Method Put -Headers $Headers
            $vappLeaseRenewResponseTask = $vappLeaseRenewResponse.Task.href
            $vappLeaseRenewResponseTaskStatus = Invoke-RestMethod -Uri $vappLeaseRenewResponseTask -Method Get -Headers $Headers
            $vappLeaseRenewResponseTaskCheckTime = Get-Date
            $vappLeaseRenewResponseTaskTimeElapsed = (New-TimeSpan –Start $vappLeaseRenewResponseTaskStartTime –End $vappLeaseRenewResponseTaskCheckTime).TotalMinutes
            while ($vappLeaseRenewResponseTaskStatus.Task.status -notlike "success" -and $vappLeaseRenewResponseTaskTimeElapsed -lt 5) {
                $vappLeaseRenewResponseTaskStatus = Invoke-RestMethod -Uri $vappLeaseRenewResponseTask -Method Get -Headers $Headers
                Write-Host "Renew in progress, invoking wait for 5 seconds."
                Start-Sleep -Seconds 5
                $vappLeaseRenewResponseTaskCheckTime = Get-Date
                $vappLeaseRenewResponseTaskTimeElapsed = (New-TimeSpan –Start $vappLeaseRenewResponseTaskStartTime –End $vappLeaseRenewResponseTaskCheckTime).TotalMinutes
            }
            Write-Host "Lease renewed for vApp $($vappPage.name)." -ForegroundColor Green
            Write-Host ""
            $i++
        }
        $p++
    }
    while ($p -le $vappsPageCount)
}

$vcdHeaders = Login-Vcloud -Vcloud $vcloudHost -OrgName $vcloudOrg -UserName $vcloudUserName -Password $vcloudPassword
if ($vcdHeaders) {
    Write-Host "Logged in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Green
    Renew-VappLease -Vcloud $vcloudHost -Headers $vcdHeaders -VappsToRenew $vappsToRenew -DeploymentLeaseDays $deploymentLeaseDays -StorageLeaseDays $storageLeaseDays
} else {
    Write-Host "Failed to log in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Red
}