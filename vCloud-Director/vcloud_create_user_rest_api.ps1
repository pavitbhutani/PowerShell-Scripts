# Author: Pavit Bhutani.
# Script creates a local user in specified or all Orgs according to parameters specified.
# Specify Org name for indivudual Org or 'system' for all Orgs.

# Script variables to log in to the cloud with an existing account.
$vcloudHost = "cloud.vmware.com"
$vcloudOrg = "system"
$vcloudUserName = "username"
$vcloudPassword = "password"
$vcloudApiVersion = "31.0"

# Variables to create the new user.
$newUserName = "new-username"
$newUserPassword = "password"
$newUserFullName = "full name."
$newUserRole = "Organization Administrator"
# Specify 0 for no quota.
[int]$newUserStoredVmQuota = 10
[int]$newUserDeployedVmQuota = 10

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

# List the Org(s).
function Get-VcloudOrg {
    Param
    (   [Parameter(Mandatory=$true)]
        [string]$Vcloud,
        [Parameter(Mandatory=$true)]
        [string]$Orgname,
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers
    )
    [int32]$pageSize = 128
    $orgsOutput = @()
    if ($Orgname -like "system") {
        $orgsLookupUrl = "https://" + $Vcloud + "/api/query?type=organization&format=idrecords&pageSize=$pageSize"
    } else {
        $orgsLookupUrl = "https://" + $Vcloud + "/api/query?type=organization&format=idrecords&filter=(name==$Orgname)"
    }
    $orgsResult = (Invoke-RestMethod -Uri $orgsLookupUrl -Method Get -Headers $Headers).QueryResultRecords
    $orgsPageCount = [math]::Ceiling($orgsResult.total/$pageSize)
    [Int32]$p = 1
    do {
        Write-Host "Checking page $p of $orgsPageCount." -ForegroundColor Green
        $orgsPageLookupUrl = $orgsLookupUrl + "&page=$p"
        $orgsPage = (Invoke-RestMethod -Uri $orgsPageLookupUrl -Method Get -Headers $Headers).QueryResultRecords
        foreach ($orgPage in $orgsPage.OrgRecord) {
            $orgsInput = "" | select name, displayName, id
            $orgsInput.name = $orgPage.name
            $orgsInput.displayName = $orgPage.displayName
            $orgsInput.id = $orgPage.id.Substring(15)
            $orgsOutput += $orgsInput
        }
        $p++
    } while ($p -le $orgsPageCount)
    Write-Host "$($orgsOutput.Count) Orgs fetched." -ForegroundColor Green
    Write-Host ""
    return $orgsOutput
}

# Create the user.
function Create-OrgUser {
    Param
    (   [Parameter(Mandatory=$true)]
        [string]$Vcloud,
        [Parameter(Mandatory=$true)]
        [string]$Orgname,
        [Parameter(Mandatory=$true)]
        [string]$NewUserName,
        [Parameter(Mandatory=$true)]
        [string]$NewUserPassword,
        [Parameter(Mandatory=$true)]
        [string]$NewUserFullName,
        [Parameter(Mandatory=$true)]
        [string]$NewUserRole,
        [Parameter(Mandatory=$true)]
        [int]$NewUserStoredVmQuota,
        [Parameter(Mandatory=$true)]
        [int32]$NewUserDeployedVmQuota,
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers
    )
    Write-Host "Creating user $NewUserName with role $NewUserRole." -ForegroundColor Green
    $orgRolesLookupUrl = "https://$Vcloud/api/query?type=role&format=records"
    $orgRoles = Invoke-RestMethod -Uri $orgRolesLookupUrl -Method Get -Headers $Headers
    $orgRole = $orgRoles.QueryResultRecords.RoleRecord | ? {$_.name -like $NewUserRole}
    $orgsLookupUrl = "https://" + $Vcloud + "/api/query?type=organization&format=idrecords"
    $orgId = (Invoke-RestMethod -Uri $orgsLookupUrl -Method Get -Headers $Headers).QueryResultRecords.OrgRecord.id.Substring(15)
    if ($orgRole) {
        Write-Host "Role $NewUserRole found in the Org, creating user." -ForegroundColor Green
        $userCreateUrl = "https://$Vcloud/api/admin/org/$orgId/users"
        $userCreateType = "application/vnd.vmware.admin.user+xml"
        $userCreateBody = @"
<?xml version="1.0" encoding="UTF-8"?>
<vcloud:User
    xmlns:vcloud = "http://www.vmware.com/vcloud/v1.5"
    name = "$NewUserName">
<vcloud:FullName>$NewUserFullName</vcloud:FullName>
<vcloud:IsEnabled>true</vcloud:IsEnabled>
<vcloud:ProviderType>INTEGRATED</vcloud:ProviderType>
<vcloud:StoredVmQuota>$NewUserStoredVmQuota</vcloud:StoredVmQuota>
<vcloud:DeployedVmQuota>$NewUserDeployedVmQuota</vcloud:DeployedVmQuota>
<vcloud:Role
    href = "$($orgRole.href)"
    name = "$NewUserRole"
    type = "application/vnd.vmware.admin.role+xml"/>
<vcloud:Password>$NewUserPassword</vcloud:Password>
</vcloud:User>
"@

        try {
            $userCreateResponse = Invoke-RestMethod -Uri $userCreateUrl -Method Post -Body $userCreateBody -ContentType $userCreateType -Headers $Headers
            Write-Host "User created." -ForegroundColor Green    
        }
        catch {
            $_.Exception.Message
        }
    } else {
        Write-Host "Role $NewUserRole not found in the Org." -ForegroundColor Red
    }
    Write-Host ""
}

$vcdHeaders = Login-Vcloud -Vcloud $vcloudHost -OrgName $vcloudOrg -UserName $vcloudUserName -Password $vcloudPassword
if ($vcdHeaders) {
    Write-Host "Logged in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Green
    $orgsOutput = Get-VcloudOrg -Vcloud $vcloudHost -Orgname $vcloudOrg -Headers $vcdHeaders
    if ($orgsOutput.count -gt 1) {
        foreach ($org in $orgsOutput) {
            Write-Host "Logging in to Org $($org.name)." -ForegroundColor Green
            $vcdOrgHeaders = Login-Vcloud -Vcloud $vcloudHost -OrgName $org.name -UserName $vcloudUserName -Password $vcloudPassword
            if ($vcdOrgHeaders) {
                Create-OrgUser -Vcloud $vcloudHost -Headers $vcdOrgHeaders -Orgname $org.name -NewUserName $newUserName -NewUserPassword $newUserPassword -NewUserFullName $newUserFullName -NewUserRole $newUserRole -NewUserStoredVmQuota $newUserStoredVmQuota -NewUserDeployedVmQuota $newUserDeployedVmQuota
                Clear-Variable vcdOrgHeaders
            } else {
                Write-Host "Could not log in to Org $($org.name) using $vcloudUserName." -ForegroundColor Red
                Write-Host ""
            }
        }
    } else {
        Create-OrgUser -Vcloud $Vcloud -Headers $vcdHeaders -Orgname $vcloudOrg -NewUserName $newUserName -NewUserPassword $newUserPassword -NewUserFullName $newUserFullName -NewUserRole $newUserRole -NewUserStoredVmQuota $newUserStoredVmQuota -NewUserDeployedVmQuota $newUserDeployedVmQuota
    }
} else {
    Write-Host "Failed to log in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Red
}