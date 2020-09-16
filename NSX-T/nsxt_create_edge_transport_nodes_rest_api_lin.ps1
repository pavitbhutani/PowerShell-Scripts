# Author: Pavit Bhutani.
# Script creates NSX-T edge transport nodes with DHCP IP assignment.
# Script can be run from Powershell Core.

##Script variables for existing NSX-T components.
$nsxtIpOrFqdn = ""
$nsxtUsername = "admin"
$nsxtPassword = ""
$nsxtTransportZoneName = "TransportZone-1"
$nsxtComputeManagerName = ""
$nsxtTepIpPoolName = "IPPool-1"
$nsxtNVDSName = "N-VDS-1"
$nsxtUplinkName = "Uplink-1"
$nsxtHostSwitchProfileName = "UplinkProfile-1"

##Script variables to create NSX-T edge nodes.
$nsxtEdgeNodeNames = "edge1","edge2","edge3"
$nsxtEdgeHostNames = "edge1.domain.name","edge2.domain.name","edge3.domain.name"
$nsxtEdgePassword = ""

##Script variables for vSphere resources for edge deployment.
$nsxtEdgeManagementNetworkId = "dvportgroup-20"
$nsxtEdgeUplinkNetworkId = "dvportgroup-57"
$nsxtEdgeDatastoreId = "datastore-31"
$nsxtEdgeVsphereClusterId = "domain-c8"


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

function Create-EdgeTransportNodes {
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$NSXtManagerIpOrFqdn,
        [Parameter(Mandatory=$true)]
        [string]$ComputeManagerName,
        [Parameter(Mandatory=$true)]
        [string[]]$EdgeNames,
        [Parameter(Mandatory=$true)]
        [string[]]$EdgeHostNames,
        [Parameter(Mandatory=$true)]
        [string]$EdgePassword,
        [Parameter(Mandatory=$true)]
        [string]$EdgeManagementNetworkId,
        [Parameter(Mandatory=$true)]
        [string]$EdgeUplinkNetworkId,
        [Parameter(Mandatory=$true)]
        [string]$TransportZoneName,
        [Parameter(Mandatory=$true)]
        [string]$TepIpPoolName,
        [Parameter(Mandatory=$true)]
        [string]$NVDSName,
        [Parameter(Mandatory=$true)]
        [string]$UplinkName,
        [Parameter(Mandatory=$true)]
        [string]$HostSwitchProfileName,
        [Parameter(Mandatory=$true)]
        [string]$VsphereClusterMoid,
        [Parameter(Mandatory=$true)]
        [string]$DatastoreMoid,
        [Parameter(Mandatory=$true)]
        [hashtable]$NsxtHeaders
    )

    Write-Host "Creating edge transport nodes." -ForegroundColor Green
    $nsxtEdgeTransportNodesCreated = @()
    [Int32]$nsxtEdgeTransportNodeTimeout = 15
    $nsxtApiUrl = "https://" + $NSXtManagerIpOrFqdn + "/api/v1"

    Write-Host "Fetching transport zone $TransportZoneName." -ForegroundColor Green
    $nsxtTransportZonesUrl = $nsxtApiUrl + "/transport-zones"
    $nsxtTransportZones = Invoke-RestMethod -Uri $nsxtTransportZonesUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
    $nsxtTransportZoneId = ($nsxtTransportZones.results | ? {$_.display_name -like $TransportZoneName}).id
    if (!$nsxtTransportZoneId) {
        Write-Host "Could not fetch transport zone." -ForegroundColor Red
    }

    Write-Host "Fetching host switch profile $HostSwitchProfileName." -ForegroundColor Green
    $nsxtHostSwitchProfilesUrl = $nsxtApiUrl + "/host-switch-profiles"
    $nsxtHostSwitchProfiles = Invoke-RestMethod -Uri $nsxtHostSwitchProfilesUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
    $nsxtHostSwitchProfileId = ($nsxtHostSwitchProfiles.results | ? {$_.display_name -like $HostSwitchProfileName}).id
    if (!$nsxtHostSwitchProfileId) {
        Write-Host "Could not fetch host switch profile." -ForegroundColor Red
    }

    Write-Host "Fetching compute manager $ComputeManagerName." -ForegroundColor Green
    $nsxtComputeManagersUrl = $nsxtApiUrl + "/fabric/compute-managers"
    $nsxtComputeManagers = Invoke-RestMethod -Uri $nsxtComputeManagersUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
    $nsxtComputeManagerId = ($nsxtComputeManagers.results | ? {$_.display_name -like $ComputeManagerName}).id
    if (!$nsxtComputeManagerId) {
        Write-Host "Could not fetch compute manager." -ForegroundColor Red
    }

    Write-Host "Fetching ip pool $TepIpPoolName." -ForegroundColor Green
    $nsxtIpPoolsUrl = $nsxtApiUrl + "/pools/ip-pools"
    $nsxtIpPools = Invoke-RestMethod -Uri $nsxtIpPoolsUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
    $nsxtIpPoolId = ($nsxtIpPools.results | ? {$_.display_name -like $TepIpPoolName}).id
    if (!$nsxtIpPoolId) {
        Write-Host "Could not fetch ip pool." -ForegroundColor Red
    }

    if ($nsxtTransportZoneId -and $nsxtHostSwitchProfileId -and $nsxtComputeManagerId -and $nsxtIpPoolId) {
        $nsxtEdgeTransportNodeCreateUrl = $nsxtApiUrl + "/transport-nodes"
        $i = 0
        foreach ($edge in $EdgeNames) {
            Write-Host "Creating Edge Transport Node $edge." -ForegroundColor Green
            $nsxtEdgeTransportNodesCreatedIn = "" | select edgeName, apiBody, node_id, edgeCreated
            $nsxtEdgeTransportNodesCreatedIn.edgeName = $edge
            $nsxtEdgeTransportNodeCreateBody = @"
{
    "host_switch_spec":{
        "host_switches":[
        {
            "host_switch_name":"$NVDSName",
            "host_switch_profile_ids":[
            {
                "key":"UplinkHostSwitchProfile",
                "value":"$nsxtHostSwitchProfileId"
            }
            ],
            "pnics":[
            {
                "device_name":"fp-eth1",
                "uplink_name":"$UplinkName"
            }
            ],
            "ip_assignment_spec":{
            "ip_pool_id":"$nsxtIpPoolId",
            "resource_type":"StaticIpPoolSpec"
            }
        }
        ],
        "resource_type":"StandardHostSwitchSpec"
    },
    "transport_zone_endpoints":[
        {
        "transport_zone_id":"$nsxtTransportZoneId"
        }
    ],
    "node_deployment_info":{
        "deployment_config":{
        "vm_deployment_config":{
            "vc_id":"$nsxtComputeManagerId",
            "compute_id":"$VsphereClusterMoid",
            "storage_id":"$DatastoreMoid",
            "management_network_id":"$EdgeManagementNetworkId",
            "hostname":"$($EdgeHostNames[$i])",
            "data_network_ids":[
            "$EdgeUplinkNetworkId",
            "$EdgeUplinkNetworkId",
            "$EdgeUplinkNetworkId"
            ],
            "placement_type":"VsphereDeploymentConfig"
        },
        "form_factor":"SMALL",
        "node_user_settings":{
            "cli_username":"admin",
            "root_password":"$EdgePassword",
            "cli_password":"$EdgePassword"
        }
        },
        "resource_type":"EdgeNode"
    },
    "resource_type":"TransportNode",
    "display_name":"$edge"
}
"@
            $nsxtEdgeTransportNodesCreatedIn.apiBody = $nsxtEdgeTransportNodeCreateBody
            $nsxtEdgeTransportNodeStartTime = Get-Date
            $nsxtEdgeTransportNodeCreateResponse = Invoke-RestMethod -Uri $nsxtEdgeTransportNodeCreateUrl -Method Post -Body $nsxtEdgeTransportNodeCreateBody -Headers $NsxtHeaders -SkipCertificateCheck
            if ($null -ne $nsxtEdgeTransportNodeCreateResponse) {
                Write-Host "Edge Transport node $edge created, checking status." -ForegroundColor Green
                $nsxtEdgeTransportNodeStatusUrl =  $nsxtEdgeTransportNodeCreateUrl + "/" + $nsxtEdgeTransportNodeCreateResponse.node_id + "/status"
                $nsxtEdgeTransportNodesCreatedIn.node_id = $nsxtEdgeTransportNodeCreateResponse.node_id
                try {
                    $nsxtEdgeTransportNodeStatus = Invoke-RestMethod -Uri $nsxtEdgeTransportNodeStatusUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
                } catch {
                    Write-Host "Exception: $($_.Exception.Message)." -ForegroundColor Yellow
                }
                $nsxtEdgeTransportNodeCheckTime = Get-Date
                $nsxtEdgeTransportNodeTimeElapsed = (New-TimeSpan –Start $nsxtEdgeTransportNodeStartTime –End $nsxtEdgeTransportNodeCheckTime).TotalMinutes

                while ($nsxtEdgeTransportNodeStatus.status -notlike "UP" -and $nsxtEdgeTransportNodeTimeElapsed -lt $nsxtEdgeTransportNodeTimeout) {
                    try {
                        $nsxtEdgeTransportNodeStatus = Invoke-RestMethod -Uri $nsxtEdgeTransportNodeStatusUrl -Method Get -Headers $NsxtHeaders -SkipCertificateCheck
                    } catch {
                        Write-Host "Exception: $($_.Exception.Message), retrying after 30 seconds." -ForegroundColor Yellow
                    }
                    Start-Sleep -Seconds 30
                    $nsxtEdgeTransportNodeCheckTime = Get-Date
                    $nsxtEdgeTransportNodeTimeElapsed = (New-TimeSpan –Start $nsxtEdgeTransportNodeStartTime –End $nsxtEdgeTransportNodeCheckTime).TotalMinutes
                }

                if ($nsxtEdgeTransportNodeStatus.status -like "UP") {
                    Write-Host "Edge Transport node $edge deployed successfully." -ForegroundColor Green
                    $nsxtEdgeTransportNodesCreatedIn.edgeCreated = $true
                } else {
                    Write-Host "Could not deploy Edge Transport node $edge." -ForegroundColor Red
                }
            } else {
                Write-Host "Could not deploy Edge Transport node $edge." -ForegroundColor Red
            }
            Clear-Variable nsxtEdgeTransportNodeStatus, nsxtEdgeTransportNodeCreateResponse
            $i++
            $nsxtEdgeTransportNodesCreated += $nsxtEdgeTransportNodesCreatedIn
        }
    } else {
        Write-Host "All required NSX-T components could not be fetched, aborting." -ForegroundColor Red
    }
    return $nsxtEdgeTransportNodesCreated
}


$nsxtHeaders = Login-NSXManager -NSXManagerIpOrFqdn $nsxtIpOrFqdn -Username $nsxtUsername -Password $nsxtPassword
if ($nsxtHeaders) {
    Write-Host "Logged in to NSX Manager." -ForegroundColor Green
    $edgeTransportNodesCreated = Create-EdgeTransportNodes -NSXtManagerIpOrFqdn $nsxtIpOrFqdn -ComputeManagerName $nsxtComputeManagerName -EdgeNames $nsxtEdgeNodeNames -EdgeHostNames $nsxtEdgeHostNames -EdgePassword $nsxtEdgePassword -EdgeManagementNetworkId $nsxtEdgeManagementNetworkId -EdgeUplinkNetworkId $nsxtEdgeUplinkNetworkId -TransportZoneName $nsxtTransportZoneName -TepIpPoolName $nsxtTepIpPoolName -NVDSName $nsxtNVDSName -UplinkName $nsxtUplinkName -HostSwitchProfileName $nsxtHostSwitchProfileName -VsphereClusterMoid $nsxtEdgeVsphereClusterId -DatastoreMoid $nsxtEdgeDatastoreId -NsxtHeaders $nsxtHeaders
} else {
    Write-Host "Could not log in to NSX Manager with provided credentials." -ForegroundColor Red
}