# Author: Pavit Bhutani.
# Script configures Stage-2 for an embedded vCenter Appliance using REST API.

# Variables to configure vCenter Appliance.
$vcenterFqdnOrIp = ""
$vcenterSsoDomainName = "vsphere.local"
$vcenterSsoPassword = ""

# Variables used to generate VAMI header used for making API calls.
$vamiUsername = "root"
$vamiPassword = ""

# Generate VAMI header.
$vamiAuth = $vamiUsername + ':' + $vamiPassword
$vamiEncoded = [System.Text.Encoding]::UTF8.GetBytes($vamiAuth)
$vamiEncodedPassword = [System.Convert]::ToBase64String($vamiEncoded)
$vamiHeaders = @{"Authorization"="Basic $($vamiEncodedPassword)"}
$vamiHeaders.Add('Content-Type','application/json')

function Configure-VCSAStage2 {
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$VcenterFqdnOrIp,
        [Parameter(Mandatory=$true)]
        [hashtable]$VamiHeaders,
        [Parameter(Mandatory=$true)]
        [string]$VcenterSsoDomainName,
        [Parameter(Mandatory=$true)]
        [string]$VcenterSsoPassword
    )
    
    $vcsaDeploymentInstallStartTime = Get-Date
    [int]$vcsaDeploymentInstallTimeoutMinutes = 45
    $vcsaConfigured = "" | Select-Object apiBody, configured
    $vcsaConfigured.configured = $false
    $vcsaDeploymentInstallBody = @"
    {
        "spec": {
            "auto_answer": true,
            "vcsa_embedded": {
                "ceip_enabled": true,
                "standalone": {
                    "sso_admin_password": "$VcenterSsoPassword",
                    "sso_domain_name": "$VcenterSsoDomainName"
                }
            }
        }
    }
"@

    $vcsaConfigured.apiBody = $vcsaDeploymentInstallBody
    $vcsaVami = $VcenterFqdnOrIp + ":5480"
    $vcsaDeploymentUrl = "https://$vcsaVami/rest/vcenter/deployment"
    $vcsaDeploymentInstallUrl = $vcsaDeploymentUrl + "/install?action=start"
    Write-Host "Initiating Stage-2 for vCenter appliance $VcenterFqdnOrIp." -ForegroundColor Green
    try {
        $vcsaDeploymentInstallResponse = Invoke-RestMethod -Uri $vcsaDeploymentInstallUrl -Method Post -Headers $VamiHeaders -Body $vcsaDeploymentInstallBody -SkipCertificateCheck
    }
    catch {
        Write-Host "Exception: $($_.Exception.Message)." -ForegroundColor Red
    }
    
    if ($null -eq $vcsaDeploymentInstallResponse) {
        Write-Host "Failed to initiate Stage-2." -ForegroundColor Red
    } else {
        $vcsaDeploymentInstallStatus = Invoke-RestMethod -Uri $vcsaDeploymentUrl -Method Get -Headers $VamiHeaders -SkipCertificateCheck
        $vcsaDeploymentInstallCheckTime = Get-Date
        $vcsaDeploymentInstallTimeElapsed = (New-TimeSpan –Start $vcsaDeploymentInstallStartTime –End $vcsaDeploymentInstallCheckTime).TotalMinutes
        while (($vcsaDeploymentInstallStatus.status -like "RUNNING" -or $vcsaDeploymentInstallStatus.status -like "QUEUED" -or $vcsaDeploymentInstallStatus.state -like "INITIALIZED" -or $vcsaDeploymentInstallStatus.state -like "CONFIG_IN_PROGRESS")  -and $vcsaDeploymentInstallTimeElapsed -lt $vcsaDeploymentInstallTimeoutMinutes) {
            Write-Host "$(($vcsaDeploymentInstallStatus.subtasks | Where-Object {$_.key -like "firstboot"}).value.progress.completed)% completed, invoking wait for 30 seconds." -ForegroundColor Green
            Start-Sleep -Seconds 30
            $vcsaDeploymentInstallStatus = Invoke-RestMethod -Uri $vcsaDeploymentUrl -Method Get -Headers $VamiHeaders -SkipCertificateCheck
            $vcsaDeploymentInstallCheckTime = Get-Date
            $vcsaDeploymentInstallTimeElapsed = (New-TimeSpan –Start $vcsaDeploymentInstallStartTime –End $vcsaDeploymentInstallCheckTime).TotalMinutes
        }
    
        $vcsaDeploymentInstallStatus = Invoke-RestMethod -Uri $vcsaDeploymentUrl -Method Get -Headers $VamiHeaders -SkipCertificateCheck
        if ($vcsaDeploymentInstallStatus.state -like "CONFIGURED") {
            $vcsaConfigured.configured = $true
            Write-Host "Appliance deployment Stage-2 completed." -ForegroundColor Green
        } elseif ($vcsaDeploymentInstallTimeElapsed -gt $vcsaDeploymentInstallTimeoutMinutes) {
            Write-Host "Appliance deployment Stage-2 NOT completed in $vcsaDeploymentInstallTimeoutMinutes minutes, execution aborted." -ForegroundColor Red
        } else {
            Write-Host "Appliance deployment Stage-2 NOT completed, state: $($vcsaDeploymentInstallStatus.state)." -ForegroundColor Red
        }
    }
    return $vcsaConfigured
}

$vcsaConfigured = Configure-VCSAStage2 -VcenterFqdnOrIp $vcenterFqdnOrIp -VamiHeaders $vamiHeaders -VcenterSsoDomainName $vcenterSsoDomainName -VcenterSsoPassword $vcenterSsoPassword