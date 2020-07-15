# Author: Pavit Bhutani.
# Script creates virtual machine from a content library VM template using REST API.
# The VM template has 1 disk in this example the size of which is being increased while deploying.

# Variables to connect to vCenter and fetch the VM template.
$vcenterServername = ""
$vcenterUserName = "administrator@vsphere.local"
$vcenterPassword = ""
$contentLibraryName = ""
$vmTemplateName = ""

# Variables for VM spec.
$vmName = ""
$vmVcpuCount = ""
$vmMemoryGB = ""
# New size of the disk being deployed.
[Int32]$vmDiskSizeGB = ""

# Variables used to look up resources to deploy the VM on.
$vmFolderName = ""
$clusterName = ""
$vmHostName = ""
$resourcePoolName = ""
$portGroupName = ""
# Specify portGroupType value as STANDARD_PORTGROUP or DISTRIBUTED_PORTGROUP
$portGroupType = "DISTRIBUTED_PORTGROUP"
$datastoreName = ""

# Generate header to be used for making API calls.
$vcenterAuth = $vcenterUserName + ':' + $vcenterPassword
$vcenterEncoded = [System.Text.Encoding]::UTF8.GetBytes($vcenterAuth)
$vcenterEncodedPassword = [System.Convert]::ToBase64String($vcenterEncoded)
$vcenterHeaders = @{"Authorization"="Basic $($vcenterEncodedPassword)"}
$vcenterHeaders.Add('Content-Type','application/json')
$vcenterBaseUrl = "https://$vcenterServername/rest/"
$vcenterLoginUrl = $vcenterBaseUrl + "com/vmware/cis/session"
try {
    $vcenterLoginResponse = Invoke-RestMethod -Uri $vcenterLoginUrl -Headers $vcenterHeaders -Method POST -SkipCertificateCheck
}
catch {
    $_.Exception.Message
}

if ($vcenterLoginResponse) {
    Write-Host "Logged in to vCenter server using API." -ForegroundColor Green
    
    # Add vmware-api-session-id to the header after first login.
    $vcenterHeaders.Add(‘vmware-api-session-id’,$vcenterLoginResponse.value)

    $contentLibraryFindUrl = $vcenterBaseUrl + "com/vmware/content/library?~action=find"
    $contentLibraryFindBody = @"
    {
        "spec" :  {
            "name" :  "$contentLibraryName" ,
            "type" :  "LOCAL"
        }
    }
"@

    $contentLibraryId = (Invoke-RestMethod -Uri $contentLibraryFindUrl -Method Post -Headers $vcenterHeaders -Body $contentLibraryFindBody -ContentType "application/json" -SkipCertificateCheck).value
    if ($contentLibraryId) {
        Write-Host "Content library id: $contentLibraryId." -ForegroundColor Green
        $contentLibraryItemFindBody = @"
        {
            "spec" :  {
                "library_id" :  "$contentLibraryId" ,
                "name" :  "$vmTemplateName" 
            }
    }
"@

        $contentLibraryItemFindUrl = $vcenterBaseUrl + "com/vmware/content/library/item?~action=find"
        $contentLibraryItemId = (Invoke-RestMethod -Uri $contentLibraryItemFindUrl -Method Post -Headers $vcenterHeaders -Body $contentLibraryItemFindBody -ContentType "application/json" -SkipCertificateCheck).value
        if ($contentLibraryItemId) {
            Write-Host "Content library item id: $contentLibraryItemId." -ForegroundColor Green
            $contentLibraryItemUrl = $vcenterBaseUrl + "com/vmware/content/library/item/id:$contentLibraryItemId"
            $contentLibraryItem = Invoke-RestMethod -Uri $contentLibraryItemUrl -Method Get -Headers $vcenterHeaders -SkipCertificateCheck
            if ($contentLibraryItem.value.type -eq "vm-template") {
                Write-Host "Content library item type is vm-template." -ForegroundColor Green
                $vmTemplateLookupUrl = $vcenterBaseUrl + "vcenter/vm-template/library-items/$contentLibraryItemId"
                $vmTemplate = Invoke-RestMethod -Uri $vmTemplateLookupUrl -Method Get -Headers $vcenterHeaders -SkipCertificateCheck

                Write-Host "Looking up folder named $vmFolderName." -ForegroundColor Green
                $folderLookupUrl = $vcenterBaseUrl + "vcenter/folder?filter.names.1=$vmFolderName"
                $folderId = (Invoke-RestMethod -Uri $folderLookupUrl -Method Get -Headers $vcenterHeaders -SkipCertificateCheck).value.folder

                Write-Host "Looking up cluster named $clusterName." -ForegroundColor Green
                $clusterLookupUrl = $vcenterBaseUrl + "vcenter/cluster?filter.names.1=$clusterName"
                $clusterId = (Invoke-RestMethod -Uri $clusterLookupUrl -Method Get -Headers $vcenterHeaders -SkipCertificateCheck).value.cluster

                Write-Host "Looking up host named $vmHostName." -ForegroundColor Green
                $vmHostLookupUrl = $vcenterBaseUrl + "vcenter/host?filter.names.1=$vmHostName"
                $vmHostId = (Invoke-RestMethod -Uri $vmHostLookupUrl -Method Get -Headers $vcenterHeaders -SkipCertificateCheck).value.host

                Write-Host "Looking up resource pool named $resourcePoolName." -ForegroundColor Green
                $resourcePoolLookupUrl = $vcenterBaseUrl + "vcenter/resource-pool?filter.names.1=$resourcePoolName"
                $resourcePoolId = (Invoke-RestMethod -Uri $resourcePoolLookupUrl -Method Get -Headers $vcenterHeaders -SkipCertificateCheck).value.resource_pool
                
                Write-Host "Looking up datastore named $datastoreName." -ForegroundColor Green
                $datastoreLookupUrl = $vcenterBaseUrl + "vcenter/datastore?filter.names.1=$datastoreName"
                $datastoreId = (Invoke-RestMethod -Uri $datastoreLookupUrl -Method Get -Headers $vcenterHeaders -SkipCertificateCheck).value.datastore

                Write-Host "Looking up port group named $portGroupName, type $portGroupType." -ForegroundColor Green
                $portGroupLookupUrl = $vcenterBaseUrl + "vcenter/network?filter.names.1=$portGroupName&filter.types.1=$portGroupType"
                $portGroupId = (Invoke-RestMethod -Uri $portGroupLookupUrl -Method Get -Headers $vcenterHeaders -SkipCertificateCheck).value.network

                if (!($null -eq $datastoreId -or $null -eq $clusterId -or $null -eq $folderId -or $null -eq $vmHostId -or $null -eq $resourcePoolId -or $null -eq $portGroupId)) {
                    Write-Host "Deploying VM $vmName." -ForegroundColor Green
                    $vmDeployBody = @"
                    {
                        "spec" :  {
                            "disk_storage" :  {
                                "datastore" :  "$datastoreId"
                            } ,
                            "hardware_customization" :  {
                                "cpu_update" :  {
                                    "num_cpus" :  $vmVcpuCount ,
                                    "num_cores_per_socket" :  1
                                } ,
                                "memory_update" :  {
                                    "memory" :  $vmMemoryGB
                                } ,
                                "nics" :  [
                                    {
                                        "value" :  {
                                            "network" :  "$portGroupId"
                                        } ,
                                        "key" :  "$($vmTemplate.value.nics.key)"
                                    }
                                ] ,
                                "disks_to_update" :  [
                                    {
                                        "value" :  {
                                            "capacity" :  "$($vmDiskSizeGB*1024*1024*1024)"
                                        } ,
                                        "key" :  "$($vmTemplate.value.disks.key)"
                                    }
                                ]
                            } ,
                            "name" :  "$vmName" ,
                            "vm_home_storage" :  {
                                "datastore" :  "$datastoreId"
                            } ,
                            "placement" :  {
                                "cluster" :  "$clusterId" ,
                                "folder" :  "$folderId" ,
                                "host" :  "$vmHostId" ,
                                "resource_pool" :  "$resourcePoolId"
                            } ,
                            "powered_on" :  false
                        }
                    }
"@

                    $vmTemplateDeployUrl = $vcenterBaseUrl + "vcenter/vm-template/library-items/" + $contentLibraryItemId + "?action=deploy"
                    try {
                        $vmTemplateDeploy = Invoke-RestMethod -Uri $vmTemplateDeployUrl -Method Post -Body $vmDeployBody -Headers $vcenterHeaders -SkipCertificateCheck
                    }
                    catch {
                        $_.Exception.Message
                    }
                    
                    if ($vmTemplateDeploy) {
                        Write-Host "VM $vmName deployed successfully." -ForegroundColor Green
                    } else {
                        Write-Host "VM $vmName could not be deployed." -ForegroundColor Red
                    }
                } else {
                    Write-Host "All objects not found with specified resource variables, make sure the values are correct and try again." -ForegroundColor Red
                }
            } else {
                Write-Host "Content library item type is not vm-template, specified item type: $($contentLibraryItem.value.type)." -ForegroundColor Red
            }
        } else {
            Write-Host "Item with name $vmTemplateName not found in the Content Library." -ForegroundColor Red
        }
    } else {
        Write-Host "Content Library with name $contentLibraryName not found." -ForegroundColor Red
    }
} else {
    Write-Host "Could not log in to vCenter using API." -ForegroundColor Red
}