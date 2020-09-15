# Author: Pavit Bhutani.
# Script creates NSX-T segments based on inputs provided and can be run from Powershell Core.

##Script variables
$nsxtIpOrFqdn = ""
$nsxtUsername = "admin"
$nsxtPassword = ""
$nsxtSegmentNames = "Web-Segment","App-Segment","DB-Segment"
$nsxtSegmentCIDRs = "172.16.10.1/24","172.16.20.1/24","172.16.30.1/24"
$nsxtTransportZoneName = ""

#Verifies that NSX-T credentials provided can log in.
function Login-NSXManager {
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$NSXManagerIpOrFqdn,
        [Parameter(Mandatory=$true)]
        [string]$Username,
        [Parameter(Mandatory=$true)]
        [string]$Password
    )
    $nsxtAuth = $Username + ':' + $Password
    $nsxtEncoded = [System.Text.Encoding]::UTF8.GetBytes($nsxtAuth)
    $nsxtEncodedPassword = [System.Convert]::ToBase64String($nsxtEncoded)
    $nsxtHeaders = @{"Authorization"="Basic $($nsxtEncodedPassword)"}
    $nsxtHeaders.Add('Content-Type','application/json')
    Write-Host "Logging in to NSX Manager." -ForegroundColor Green
    $nsxtApiUrl = "https://" + $NSXManagerIpOrFqdn + "/api/v1"
    Write-Host "NSXt API URL: $nsxtApiUrl" -ForegroundColor Green
    $nsxtApplianceApiRegisterUrl = $nsxtApiUrl + "/aaa/registration-token"
    $nsxtApplianceApiRegisterResponse = Invoke-RestMethod -Uri $nsxtApplianceApiRegisterUrl -Method Post -Headers $nsxtHeaders -SkipCertificateCheck
    if ($nsxtApplianceApiRegisterResponse.token) {
        return $nsxtHeaders
    }
}

function Create-NSXtSegments {
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$NSXtManagerIpOrFqdn,
        [Parameter(Mandatory=$true)]
        [string[]]$SegmentNames,
        [Parameter(Mandatory=$true)]
        [string[]]$SegmentGatewayCIDRs,
        [Parameter(Mandatory=$true)]
        [string]$TransportZoneName,
        [Parameter(Mandatory=$true)]
        [hashtable]$NsxtHeaders
    )

    Write-Host "Creating segments." -ForegroundColor Green
    $nsxtSegmentsCreated = @()
    $nsxtPolicyApiUrl = "https://" + $NSXtManagerIpOrFqdn + "/policy/api/v1"
    $nsxtApiUrl = "https://" + $NSXtManagerIpOrFqdn + "/api/v1"
    $nsxtTransportZonesUrl = $nsxtApiUrl + "/transport-zones"
    $nsxtSegmentsUrl = $nsxtPolicyApiUrl + "/infra/segments/"
    $nsxtTransportZones = Invoke-RestMethod -Uri $nsxtTransportZonesUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
    $nsxtTransportZoneId = ($nsxtTransportZones.results | ? {$_.display_name -like $TransportZoneName}).id
    if ($nsxtTransportZoneId) {
        Write-Host "Transport zone $TransportZoneName found." -ForegroundColor Green
        $i = 0
        foreach ($segment in $SegmentNames) {
            $nsxtSegmentsCreatedIn = "" | select segmentName, apiBody, segmentCreated
            $nsxtSegmentsCreatedIn.segmentName = $segment
            Write-Host "Creating segment $segment." -ForegroundColor Green
            $nsxtSegmentCreateUrl = $nsxtSegmentsUrl + $segment
            try {
                $nsxtSegment = Invoke-RestMethod -Uri $nsxtSegmentCreateUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
            }
            catch {
                Write-Host "Segment $segment not in place, creating." -ForegroundColor Green
            }

            if ($nsxtSegment) {
                Write-Host "Segment $segment already in place, skipping." -ForegroundColor Green
            } else {
                $nsxtSegmentCreateBody = @"
            {
                "display_name":"$segment",
                "subnets": [
                {
                    "gateway_address": "$($SegmentGatewayCIDRs[$i])"
                }
                ],
                "transport_zone_path": "/infra/sites/default/enforcement-points/default/transport-zones/$nsxtTransportZoneId"
            }
"@
                $nsxtSegmentsCreatedIn.apiBody = $nsxtSegmentCreateBody
                $nsxtSegmentCreateResponse = Invoke-RestMethod -Uri $nsxtSegmentCreateUrl -Method Patch -Body $nsxtSegmentCreateBody -Headers $NsxtHeaders -SkipCertificateCheck
                $nsxtSegment = Invoke-RestMethod -Uri $nsxtSegmentCreateUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
                if ($nsxtSegment.admin_state -like "UP") {
                    Write-Host "Segment $segment created." -ForegroundColor Green
                    $nsxtSegmentsCreatedIn.segmentCreated = $true
                } else {
                    Write-Host "Segment $segment could not be created." -ForegroundColor Red
                }
            }
            Clear-Variable nsxtSegment
            $i++
            $nsxtSegmentsCreated += $nsxtSegmentsCreatedIn
        }
    } else {
        Write-Host "Transport zone $TransportZoneName not found." -ForegroundColor Red
    }
    return $nsxtSegmentsCreated
}

$nsxtHeaders = Login-NSXManager -NSXManagerIpOrFqdn $nsxtIpOrFqdn -Username $nsxtUsername -Password $nsxtPassword
if ($nsxtHeaders) {
    Write-Host "Logged in to NSX Manager." -ForegroundColor Green
    $nsxtSegmentsCreated = Create-NSXtSegments -NSXtManagerIpOrFqdn $nsxtIpOrFqdn -SegmentNames $nsxtSegmentNames -SegmentGatewayCIDRs $nsxtSegmentCIDRs -TransportZoneName $nsxtTransportZoneName -NsxtHeaders $nsxtHeaders
} else {
    Write-Host "Could not log in to NSX Manager with provided credentials." -ForegroundColor Red
}