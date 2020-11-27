# Author: Pavit Bhutani.
# Script enables/disables all Orgs in vCD

# Script variables.
$vcloudHost = ""
$vcloudOrg = "system"
# Provider user with system administrator rights.
$vcloudUserName = ""
$vcloudPassword = ""
$vcloudApiVersion = "31.0"
# Specify powerAction as 'enable' or 'disable'.
$accessAction = "enable"

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

# Perform access action on all Orgs.
function EditAccess-AllOrgs {
    Param
    (   [Parameter(Mandatory=$true)]
        [string]$Vcloud,
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers,
        [Parameter(Mandatory=$true)]
        [string]$AccessAction
    )
    
    [int32]$pageSize = 128
    $orgsLookupUrl = "https://" + $Vcloud + "/api/query?type=organization&format=records&pageSize=$pageSize"
    $orgs = (Invoke-RestMethod -Uri $orgsLookupUrl -Method Get -Headers $Headers).QueryResultRecords

    if ($AccessAction -like "enable") {
        $orgAccessAction = "/action/enable"
    } elseif ($AccessAction -like "disable") {
        $orgAccessAction = "/action/disable"
    }

    $orgsPageCount = [math]::Ceiling($orgs.total/$pageSize)
    [Int32]$p = 1
    do {
        [Int32]$i = 1
        $orgsPageLookupUrl = $orgsLookupUrl + "&page=$p"
        $orgsPage = Invoke-RestMethod -Uri $orgsPageLookupUrl -Method Get -Headers $Headers
        foreach ($orgPage in $orgsPage.QueryResultRecords.OrgRecord) {
            Write-Host ""
            Write-Host "Checking Org $($orgPage.name), $i of $($orgs.total)." -ForegroundColor Green
            $orgAccessActionUrl = ((Invoke-RestMethod -Uri $orgPage.href -Method Get -Headers $Headers).Org.Link | ? {$_.rel -like "alternate"}).href + $orgAccessAction
            try {
                $orgAccessActionResponse = Invoke-RestMethod -Uri $orgAccessActionUrl -Method Post -Headers $Headers
                Write-Host "Org access edited." -ForegroundColor Green
            } catch {
                $_.Exception.Message
            }
            $i++
        }
        $p++
    } while ($p -le $orgsPageCount)
}

$vcdHeaders = Login-Vcloud -Vcloud $vcloudHost -OrgName $vcloudOrg -UserName $vcloudUserName -Password $vcloudPassword
if ($vcdHeaders) {
    Write-Host "Logged in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Green
    EditAccess-AllOrgs -Vcloud $vcloudHost -AccessAction $accessAction -Headers $vcdHeaders
} else {
    Write-Host "Failed to log in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Red
}