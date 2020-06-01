##Script variables
$vcUsername = "administrator@vsphere.local"
$vcPassword = "VMware123!"
$vcPort = "443"
$vcIpOrFqdn = "10.105.73.169"
$nsxtIpOrFqdn = "10.105.73.170"
$nsxtUsername = "admin"
$nsxtPassword = "VMware123!VMware123!"

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

function Get-SSLThumbprints {
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$IpOrUrl,
        [Parameter(Mandatory=$true)]
        [string]$Port
    )
    
    if ($IsMacOS -eq $true -or $IsLinux -eq $true) {
        $url = $IpOrUrl + ":" + $Port
        $sslThumbprints = "" | select sha1, sha256
        $sslThumbprintSha256 = openssl s_client -connect $url | openssl x509 -noout -fingerprint -sha256
        if ($sslThumbprintSha256) {
            $sslThumbprints.sha256 = $sslThumbprintSha256.Substring(19)
        } else {
            $sslThumbprints.sha256 = $null
        }
        $sslThumbprintSha1 = openssl s_client -connect $url | openssl x509 -noout -fingerprint -sha1
        if ($sslThumbprintSha1) {
            $sslThumbprints.sha1 = $sslThumbprintSha1.Substring(17)
        } else {
            $sslThumbprints.sha1 = $null
        }
        return $sslThumbprints
    } elseif ($IsWindows -eq $true) {
        add-type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
            public class IDontCarePolicy : ICertificatePolicy {
            public IDontCarePolicy() {}
            public bool CheckValidationResult(
                ServicePoint sPoint, X509Certificate cert,
                WebRequest wRequest, int certProb) {
                return true;
            }
        }
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object IDontCarePolicy
        $url = "https://" + $IpOrUrl
        $urlContent = Invoke-RestMethod -Uri $url -Method Get
        $endpointRequest = [System.Net.Webrequest]::Create("$url")
        $cert = $endpointRequest.ServicePoint.Certificate
        $certBytes = $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        Set-Content -Value $certBytes -encoding byte -Path $ENV:TMP\cert-temp
        $sslThumbprints = "" | select sha1, sha256
        $sslThumbprints.sha256 = (Get-FileHash -Path $ENV:TMP\cert-temp -Algorithm SHA256).Hash -replace '(..(?!$))','$1:'
        $sslThumbprints.sha1 = (Get-FileHash -Path $ENV:TMP\cert-temp -Algorithm SHA1).Hash -replace '(..(?!$))','$1:'
        return $sslThumbprints
    }
}

function Register-ComputeManagerWithNSXManager {
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$NSXManagerIpOrFqdn,
        [Parameter(Mandatory=$true)]
        [hashtable]$NsxtHeaders,
        [Parameter(Mandatory=$true)]
        [string]$VcenterIpOrFqdn,
        [Parameter(Mandatory=$true)]
        [string]$VcenterUsername,
        [Parameter(Mandatory=$true)]
        [string]$VcenterPassword,
        [Parameter(Mandatory=$true)]
        [string]$VcenterSHA256Thumbprint
    )
    $nsxtRegisteredWithVcenter = "" | select registered, connected
    $nsxtRegisteredWithVcenter.registered = $false
    $nsxtRegisteredWithVcenter.connected = $false
    Write-Host "Registering NSXt appliance with vCenter server." -ForegroundColor Green
    $nsxtApiUrl = "https://" + $NSXManagerIpOrFqdn + "/api/v1"
    $nsxtRegisterComputeManagerBody = @"
    {
        "server": "$VcenterIpOrFqdn",
        "origin_type": "vCenter",
        "display_name": "$VcenterIpOrFqdn",
        "credential" : {
        "credential_type" : "UsernamePasswordLoginCredential",
        "username": "$VcenterUsername",
        "password": "$VcenterPassword",
        "thumbprint": "$VcenterSHA256Thumbprint"
        }
    }
"@

    $nsxtRegisterComputeManagerUrl = $nsxtApiUrl + "/fabric/compute-managers"
    Write-Host "Compute Manager register Url: $nsxtRegisterComputeManagerUrl" -ForegroundColor Green
    $nsxtRegisterComputeManagerResponse = Invoke-RestMethod -Uri $nsxtRegisterComputeManagerUrl -Method Post -Headers $NsxtHeaders -Body $nsxtRegisterComputeManagerBody -SkipCertificateCheck
    if ($nsxtRegisterComputeManagerResponse.display_name) {
        $nsxtRegisteredWithVcenter.registered = $true
        Write-Host "Compute Manager registered successfully, checking connection status." -ForegroundColor Green
        Write-Host "Compute Manager id: $($nsxtRegisterComputeManagerResponse.id)." -ForegroundColor Green
        $nsxtComputeManagerStatusStartTime = Get-Date
        $nsxtComputeManagerStatusUrl = $nsxtApiUrl + "/fabric/compute-managers/" + $nsxtRegisterComputeManagerResponse.id + "/status"
        $nsxtComputeManagerStatusResponse = Invoke-RestMethod -Uri $nsxtComputeManagerStatusUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
        $nsxtComputeManagerStatusCheckTime = Get-Date
        $nsxtComputeManagerStatusTimeElapsed = (New-TimeSpan –Start $nsxtComputeManagerStatusStartTime –End $nsxtComputeManagerStatusCheckTime).TotalMinutes
        while ($nsxtComputeManagerStatusResponse.connection_status -notlike "UP" -and $nsxtComputeManagerStatusTimeElapsed -lt 5) {
            Write-Host "Compute Manager connection status: $($nsxtComputeManagerStatusResponse.connection_status), invoking wait for 5 seconds."
            Start-Sleep -Seconds 5
            $nsxtComputeManagerStatusResponse = Invoke-RestMethod -Uri $nsxtComputeManagerStatusUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
            $nsxtComputeManagerStatusCheckTime = Get-Date
            $nsxtComputeManagerStatusTimeElapsed = (New-TimeSpan –Start $nsxtComputeManagerStatusStartTime –End $nsxtComputeManagerStatusCheckTime).TotalMinutes
        }

        if ($nsxtComputeManagerStatusResponse.connection_status -like "UP") {
            $nsxtRegisteredWithVcenter.connected = $true
            Write-Host "Compute Manager connection status is UP." -ForegroundColor Green
        } else {
            Write-Host "Compute Manager not connected to NSX Manager." -ForegroundColor Red
        }
    } else {
        Write-Host "Compute Manager could not be registered." -ForegroundColor Red
    }
    return $nsxtRegisteredWithVcenter
}

$nsxtHeaders = Login-NSXManager -NSXManagerIpOrFqdn $nsxtIpOrFqdn -Username $nsxtUsername -Password $nsxtPassword
if ($nsxtHeaders) {
    Write-Host "Logged in to NSX Manager." -ForegroundColor Green
    Write-Host "Fetching SSL thumbprints of vCenter server." -ForegroundColor Green
    $sslThumbprints = Get-SSLThumbprints -IpOrUrl $vcIpOrFqdn -Port $vcPort
    if ($sslThumbprints.sha256 -ne $null) {
        Write-Host "SSL thumbprints for vCenter server fetched." -ForegroundColor Green
        $nsxtRegistered = Register-ComputeManagerWithNSXManager -NSXManagerIpOrFqdn $nsxtIpOrFqdn -NsxtHeaders $nsxtHeaders -VcenterIpOrFqdn $vcIpOrFqdn -VcenterUsername $vcUsername -VcenterPassword $vcPassword -VcenterSHA256Thumbprint $sslThumbprints.sha256
    } else {
        Write-Host "Could not fetch SSL thumbprints of vCenter server." -ForegroundColor Red
    }
} else {
    Write-Host "Could not log in to NSX Manager with provided credentials." -ForegroundColor Red
}