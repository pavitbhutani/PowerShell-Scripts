# Author: Pavit Bhutani.
# Script lists all users in an Org with various other properties.

# Script variables.
$vcloudHost = ""
$vcloudOrg = ""
$vcloudUserName = ""
$vcloudPassword = ""
$vcloudApiVersion = ""

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
function Get-OrgUsers {
    Param
    (   [Parameter(Mandatory=$true)]
        [string]$Vcloud,
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers
    )
    [int32]$pageSize = 128
    $usersOutput = @()
    $usersLookupUrl = "https://" + $Vcloud + "/api/query?type=user&format=records&pageSize=$pageSize"
    $users = (Invoke-RestMethod -Uri $usersLookupUrl -Method Get -Headers $Headers).QueryResultRecords
    $usersPageCount = [math]::Ceiling($users.total/$pageSize)
    [Int32]$p = 1
    do {
        Write-Host "Checking page $p of $usersPageCount." -ForegroundColor Green
        $usersPageLookupUrl = $usersLookupUrl + "&page=$p"
        $usersPage = (Invoke-RestMethod -Uri $usersPageLookupUrl -Method Get -Headers $Headers).QueryResultRecords
        foreach ($userPage in $usersPage.UserRecord) {
            $usersInput = "" | select name, fullName, userRole, isEnabled, isLdapUser, identityProviderType
            $usersInput.name = $userPage.name
            $usersInput.fullName = $userPage.fullName
            $usersInput.userRole = $userPage.roleNames
            $usersInput.isEnabled = $userPage.isEnabled
            $usersInput.isLdapUser = $userPage.isLdapUser
            $usersInput.identityProviderType = $userPage.identityProviderType
            $usersOutput += $usersInput
        }
        $p++
    }
    while ($p -le $usersPageCount)
    Write-Host "Org users fetched." -ForegroundColor Green
    return $usersOutput
}

$vcdHeaders = Login-Vcloud -Vcloud $vcloudHost -OrgName $vcloudOrg -UserName $vcloudUserName -Password $vcloudPassword
if ($vcdHeaders) {
    Write-Host "Logged in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Green
    $orgUsers = Get-OrgUsers -Vcloud $vcloudHost -Headers $vcdHeaders
} else {
    Write-Host "Failed to log in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Red
}