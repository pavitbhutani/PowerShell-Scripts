# Author: Pavit Bhutani.
# Script creates virtual machine from a Windows template.
# Also creates a non-persistent os customization spec and applies it to the VM.
# Prompts for details like cluster, datastore, portgroup etc.

# Variables to connect to vCenter and fetch the VM template.
$vcenterServername = ""
$vcenterUserName = ""
$vcenterPassword = ""
$vmTemplateName = ""

# Variables used to deploy the VM.
$vmName = ""
$vmSpecName = ""
$organizationName = ""
$vmIpAddress = ""
$vmSubnetMask = ""
$vmDefaultGateway = ""
$vmDnsServer = ""
$vmVcpuCount = ""
$vmMemoryGB = ""
$vmAdminPassword = ""
# Check for list of time zones here: https://pubs.vmware.com/vsphere-51/index.jsp?topic=%2Fcom.vmware.powercli.cmdletref.doc%2FNew-OSCustomizationSpec.html
$vmTimeZone = ""

Connect-VIServer -Server $vcenterServerName -User $vcenterUsername -Password $vcenterPassword
if ($global:DefaultVIServers.Name -contains $vcenterServerName) {
    Write-Host "Logged in to vCenter server." -ForegroundColor Green

    Write-Host ""
    $vmTemplate = Get-Template -Name $vmTemplateName
    if ($vmTemplate) {
        Write-Host "VM template with name $vmTemplateName found" -ForegroundColor Green
        $clusters = Get-Cluster | Sort-Object Name
        if ($clusters) {
            Write-Host "$($clusters.Count) cluster(s) found." -ForegroundColor Green
            if ($clusters.Count -gt 1) {
                $clusterInfo = @()
                [int32]$i = 1
                Write-Host "Select cluster to deploy the VM:"
                foreach ($cluster in $clusters) {
                    $clusterInfoInput = "" | select name, sequence
                    $clusterInfoInput.name = $cluster.Name
                    $clusterInfoInput.sequence = $i
                    Write-Host "$i. $($cluster.Name)."
                    $i++
                    $clusterInfo += $clusterInfoInput
                }
                $userClusterInput = Read-Host "Select cluster number (1, 2 etc.)"
                $userClusterName = ($clusterInfo | ? {$_.sequence -like $userClusterInput}).name
                Write-Host "Deploying VM to cluster $userClusterName."
                $clusterToDeploy = Get-Cluster -Name $userClusterName
            } else {
                Write-Host "Deploying VM to cluster $($clusters.name)."
                $clusterToDeploy = $clusters
            }
        
            Write-Host ""
            $datastores = $clusterToDeploy | Get-Datastore | Sort-Object Name
            if ($datastores) {
                Write-Host "$($datastores.Count) datastore(s) found." -ForegroundColor Green
                if ($datastores.Count -gt 1) {
                    $datastoreInfo = @()
                    [int32]$j = 1
                    Write-Host "Select datastore to deploy the VM:"
                    foreach ($datastore in $datastores) {
                        $datastoreInfoInput = "" | select name, sequence
                        $datastoreInfoInput.name = $datastore.Name
                        $datastoreInfoInput.sequence = $j
                        Write-Host "$j. $($datastore.Name)."
                        $j++
                        $datastoreInfo += $datastoreInfoInput
                    }
                    $userDatastoreInput = Read-Host "Select datastore number (1, 2 etc.)"
                    $userDatastoreName = ($datastoreInfo | ? {$_.sequence -like $userDatastoreInput}).name
                    Write-Host "Deploying VM to datastore $userDatastoreName."
                    $datastoreToDeploy = Get-Datastore -Name $userDatastoreName
                } else {
                    Write-Host "Deploying VM to datastore $($datastores.name)."
                    $datastoreToDeploy = $datastores
                }

                Write-Host "Creating OS customization spec." -ForegroundColor Green
                $osCustomizationSpec = New-OSCustomizationSpec -AdminPassword $vmAdminPassword -Name $vmSpecName -OSType Windows -FullName Administrator -OrgName $organizationName -NamingScheme Fixed -NamingPrefix $vmName -TimeZone $vmTimeZone -Type NonPersistent -Workgroup Workgroup -ChangeSid
                if ($osCustomizationSpec) {
                    Write-Host "OS customization spec created, applying Nic mapping to it and creating VM." -ForegroundColor Green
                    Get-OSCustomizationNicMapping -OSCustomizationSpec $osCustomizationSpec | Set-OSCustomizationNicMapping -IpMode UseStaticIp -IpAddress $vmIpAddress -SubnetMask $vmSubnetMask -DefaultGateway $vmDefaultGateway -Dns $vmDnsServer
                    $vmCreate = New-VM -Name $vmName -Template $vmTemplate -VMHost ($clusterToDeploy | Get-VMHost | Get-Random) -Datastore $datastoreToDeploy -OSCustomizationSpec $osCustomizationSpec
                    if ($vmCreate) {
                        Write-Host "VM created, changing CPU and memory." -ForegroundColor Green
                        $vmCreate | Set-VM -NumCpu $vmVcpuCount -MemoryGB $vmMemoryGB -Confirm:$false
                        Write-Host ""
                        $vmNetworkAdapters = $vmCreate | Get-NetworkAdapter
                        if ($vmNetworkAdapters) {
                            Write-Host "$($vmNetworkAdapters.Count) network adapters found on the VM." -ForegroundColor Green
                            $networkAdapterInfo = @()
                            foreach ($vmNetworkAdapter in $vmNetworkAdapters) {
                                $networkAdapterInfoInput = "" | select name, portGroup
                                $networkAdapterInfoInput.name = $vmNetworkAdapter.Name
                                Write-Host ""
                                Write-Host "Select port group for $($vmNetworkAdapter.Name)."  -ForegroundColor Green
                                $vmPortGroups = $vmCreate.VMHost | Get-VirtualPortGroup | select Name, VirtualSwitch | ? {$_.Name -notlike "*DVUplinks*" -and $_.Name -notlike "Management Network"}
                                $vmPortGroupInfo = @()
                                [int32]$k = 1
                                foreach ($vmPortGroup in $vmPortGroups) {
                                    $vmPortGroupInfoInput = "" | select name, virtualSwitch, switchType, sequence
                                    $vmPortGroupInfoInput.name = $vmPortGroup.Name
                                    $vmPortGroupInfoInput.virtualSwitch = $vmPortGroup.VirtualSwitch
                                    $vmPortGroupInfoInput.sequence = $k
                                    Write-Host "$k. Port group name: $($vmPortGroup.Name), vSwitch: $($vmPortGroup.VirtualSwitch)."
                                    $k++
                                    $vmPortGroupInfo += $vmPortGroupInfoInput
                                }
                                $userPortGroupInput = Read-Host "Select port group number (1, 2 etc.)"
                                $userPortGroupName = ($vmPortGroupInfo | ? {$_.sequence -like $userPortGroupInput}).name
                                $networkAdapterInfoInput.portGroup = $userPortGroupName
                                if ($vmPortGroup.ExtensionData.key -like "dvportgroup*") {
                                    $vmPortGroupInfoInput.switchType = "Distributed"
                                    Set-NetworkAdapter -NetworkAdapter $vmNetworkAdapter -Portgroup (Get-VDPortGroup -Name $userPortGroupName) -Confirm:$false
                                } else {
                                    $vmPortGroupInfoInput.switchType = "Standard"
                                    Set-NetworkAdapter -NetworkAdapter $vmNetworkAdapter -Portgroup (Get-VirtualPortGroup -VMHost $vmCreate.VMHost -Name $userPortGroupName) -Confirm:$false
                                }
                                $networkAdapterInfo += $networkAdapterInfoInput
                            }
                        } else {
                            Write-Host "No network adapters found on the VM." -ForegroundColor Yellow
                        }

                        Write-Host ""
                        $vmPowerOn = Read-Host "Power on the VM? (y/n)"
                        if ($vmPowerOn -eq "y") {
                            Write-Host "Powering on the VM." -ForegroundColor Green
                            $vmCreate | Start-VM -Confirm:$false
                        } else {
                            Write-Host "Not powering on the VM." -ForegroundColor Green
                        }
                        Write-Host ""
                        Write-Host "Script execution completed." -ForegroundColor Green
                        
                    } else {
                        Write-Host "Could not create VM, terminating execution." -ForegroundColor Red
                    }
                } else {
                    Write-Host "Could not create OS customization spec, terminating execution." -ForegroundColor Red
                }
            } else {
                Write-Host "No datastore found, terminating execution." -ForegroundColor Red
            }
        } else {
            Write-Host "No cluster found, terminating execution." -ForegroundColor Red
        }
    } else {
        Write-Host "VM template with name $vmTemplateName not found, terminating execution." -ForegroundColor Red
    }
} else {
    Write-Host "Could not log in to vCenter server." -ForegroundColor Red
}