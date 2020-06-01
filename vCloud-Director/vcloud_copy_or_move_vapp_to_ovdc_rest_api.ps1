# Author: Pavit Bhutani.
# Script copies or moves a vApp to an Org Vdc within the same Org.
# Specify COPY or MOVE in the copyAction variable.


# Script variables.
$vcloudHost = "apac-labs-cloud.vmware.com"
$vcloudOrg = "test"
$vcloudUserName = "labadmin"
$vcloudPassword = "GSSlabadmin!"
$vcloudApiVersion = "31.0"
$ovdcName = "test-ovdc"
$copyAction = "COPY"
$vappName = "pavit-test"
# Specify this variable when choosing to copy vApp.
$copiedVappName = "pavit-test-copy"


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
function Copy-VappToOvdc {
    Param
    (   [Parameter(Mandatory=$true)]
        [string]$Vcloud,
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers,
        [Parameter(Mandatory=$true)]
        [string]$VappName,
        [Parameter(Mandatory=$true)]
        [string]$OrgVdcName,
        [Parameter(Mandatory=$true)]
        [ValidateSet("COPY","MOVE")]
        [string]$Action,
        [Parameter(Mandatory=$false)]
        [string]$CopiedVappName
    )
    
    if ($Action -eq "COPY") {
        $sourceDelete = "false"
        $destinationVappName = $CopiedVappName
    } else {
        $sourceDelete = "true"
        $destinationVappName = $VappName
    }
    $orgVdcLookupUrl = "https://" + $Vcloud + "/api/query?type=orgVdc&format=records&filter=(name==$OrgVdcName)"
    $orgVdc = (Invoke-RestMethod -Uri $orgVdcLookupUrl -Method Get -Headers $Headers).QueryResultRecords.OrgVdcRecord
    if ($orgVdc) {
        Write-Host "Org Vdc with name $OrgVdcName found." -ForegroundColor Green
        $vappLookupUrl = "https://" + $Vcloud + "/api/query?type=vApp&format=records&filter=(name==$VappName)"
        $vapp = (Invoke-RestMethod -Uri $vappLookupUrl -Method Get -Headers $Headers).QueryResultRecords.VAppRecord
        if ($vapp) {
            Write-Host "vApp with name $VappName found." -ForegroundColor Green
            $vappDetails = (Invoke-RestMethod -Uri $vapp.href -Method Get -Headers $Headers).VApp
            $vappDescription = $vappDetails.Description
            $orgVdcCloneVappUrl = $orgVdc.href + "/action/cloneVApp"
            $copyVappBody = @"
<?xml version="1.0" encoding="UTF-8"?>
<vcloud:CloneVAppParams
    xmlns:vcloud = "http://www.vmware.com/vcloud/v1.5"
    deploy = "false"
    name = "$destinationVappName"
    powerOn = "false">
<vcloud:Description>$vappDescription</vcloud:Description>
<vcloud:Source
    href = "$($vapp.href)"/>
<vcloud:IsSourceDelete>$sourceDelete</vcloud:IsSourceDelete>
</vcloud:CloneVAppParams>
"@

            $copyVappResponse = Invoke-RestMethod -Uri $orgVdcCloneVappUrl -Method Post -Headers $Headers -ContentType "application/vnd.vmware.vcloud.cloneVAppParams+xml" -Body $copyVappBody
            $copyVappTask = $copyVappResponse.VApp.Tasks.Task.href
            if ($copyVappTask) {
                $copyVappTaskStatus = (Invoke-RestMethod -Uri $copyVappTask -Method Get -Headers $Headers).Task.status
                while ($copyVappTaskStatus -like "running" -or $copyVappTaskStatus -like "queued") {
                    $copyVappTaskStatus = (Invoke-RestMethod -Uri $copyVappTask -Method Get -Headers $Headers).Task.status
                    $copyVappTaskStatusProgress = (Invoke-RestMethod -Uri $copyVappTask -Method Get -Headers $Headers).Task.progress
                    if ($copyVappTaskStatusProgress) {
                        Write-Host "Copy/move task progress is $copyVappTaskStatusProgress%, invoking wait for 30 seconds."
                    } else {
                        Write-Host "Copy/move task is in progress, invoking wait for 30 seconds."
                    }
                    Start-Sleep -Seconds 30
                }
                Write-Host "vApp copied/moved successfully." -ForegroundColor Green
            } else {
                Write-Host "Could not initiate task to copy/move vApp." -ForegroundColor Red
            }
        } else {
            Write-Host "Could not find vApp with name $VappName." -ForegroundColor Red
        }
    } else {
        Write-Host "Could not find Org Vdc with name $OrgVdcName, terminating execution." -ForegroundColor Red
    }
}

$vcdHeaders = Login-Vcloud -Vcloud $vcloudHost -OrgName $vcloudOrg -UserName $vcloudUserName -Password $vcloudPassword
if ($vcdHeaders) {
    Write-Host "Logged in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Green
    if ($copyAction -eq "COPY") {
        Copy-VappToOvdc -Vcloud $vcloudHost -Headers $vcdHeaders -VappName $vappName -OrgVdcName $ovdcName -Action $copyAction -CopiedVappName $copiedVappName
    } else {
        Copy-VappToOvdc -Vcloud $vcloudHost -Headers $vcdHeaders -VappName $vappName -OrgVdcName $ovdcName -Action $copyAction
    }
} else {
    Write-Host "Failed to log in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Red
}