$vcenterServerName = ""
$vcenterUserName = ""
$vcenterPassword = ""
$vcenterLicense = ""

function Update-VcenterLicense {
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$VcenterServerFqdnOrIp,
        [Parameter(Mandatory=$true)]
        [string]$LicenseKey
    )
    
    Write-Host "Fetching vCenter server object."
    $vcenterServerObject = $global:DefaultVIServer | ? {$_.Name -like $VcenterServerFqdnOrIp}
    if ($vcenterServerObject) {
        Write-Host "vCenter server object fetched, adding license key."
        $LicenseManager = Get-View $vcenterServerObject.ExtensionData.Content.LicenseManager
        $LicenseManager.AddLicense($LicenseKey,$null)
        $LicenseAssignmentManager = Get-View $LicenseManager.LicenseAssignmentManager
        $LicenseAssignmentManager.UpdateAssignedLicense($vcenterServerObject.InstanceUuid,$LicenseKey,$null)
        Write-Host "License key added." -ForegroundColor Green
    } else {
        Write-Host "Could not fetch vCenter server object." -ForegroundColor Red
    }
}

Connect-VIServer -Server $vcenterServerName -User $vcenterUsername -Password $vcenterPassword
if ($global:DefaultVIServers.Name -contains $vcenterServerName) {
    Write-Host "Logged in to vCenter server." -ForegroundColor Green
    Update-VcenterLicense -VcenterServerFqdnOrIp $vcenterServerName -LicenseKey $vcenterLicense
} else {
    Write-Host "Could not log in to vCenter server." -ForegroundColor Red
}