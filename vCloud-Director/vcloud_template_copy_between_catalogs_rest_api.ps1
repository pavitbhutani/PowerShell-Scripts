# Author: Pavit Bhutani.
# Script copies all templates and media from sourceCatalog to destinationCatalog using stagingCatalog.
# Content is first copied from source to staging, and then moved from staging to destination.
# Does not delete content from source catalog.

# Script variables.
$sourceCatalogName = ""
$stagingCatalogName = ""
$destinationCatalogName = ""
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
function Move-ItemsToCatalog {
    Param
    (   [Parameter(Mandatory=$true)]
        [string]$Vcloud,
        [Parameter(Mandatory=$true)]
        [hashtable]$Headers,
        [Parameter(Mandatory=$true)]
        [string]$OrgName,
        [Parameter(Mandatory=$true)]
        [string]$SourceCatalogName,
        [Parameter(Mandatory=$true)]
        [string]$StagingCatalogName,
        [Parameter(Mandatory=$true)]
        [string]$DestinationCatalogName
    )
    
    $catalogLookupUrl = "https://" + $Vcloud + "/api/query?type=catalog&format=records&filter=(orgName==$OrgName)"
    $catalogs = (Invoke-RestMethod -Uri $catalogLookupUrl -Method Get -Headers $Headers).QueryResultRecords.CatalogRecord
    $sourceCatalog = $catalogs | ? {$_.name -like "$SourceCatalogName"}
    $stagingCatalog = $catalogs | ? {$_.name -like "$StagingCatalogName"}
    $destinationCatalog = $catalogs | ? {$_.name -like "$DestinationCatalogName"}

    $destinationCatalogItems = (Invoke-RestMethod -Uri $destinationCatalog.href -Method Get -Headers $Headers).Catalog.CatalogItems.CatalogItem
    $sourceCatalogItems = (Invoke-RestMethod -Uri $sourceCatalog.href -Method Get -Headers $Headers).Catalog.CatalogItems.CatalogItem
    $stagingCatalogCopyUrl = $stagingCatalog.href + "/action/copy"
    $destinationCatalogMoveUrl = $destinationCatalog.href + "/action/move"

    foreach ($catalogItem in $sourceCatalogItems) {
        Write-Host ""
        Write-Host "Checking if $($catalogItem.name) is present in $($destinationCatalog.name)." -ForegroundColor Green
        if (!($destinationCatalogItems.name -contains $catalogItem.name)) { 
            Write-Host "$($catalogItem.name) not found in $($destinationCatalog.name), starting copy." -ForegroundColor Green
            Write-Host "Copying $($catalogItem.name) to catalog $($stagingCatalog.name)." -ForegroundColor Green
            $copyItemToStagingCatalogBody = @"
        <CopyOrMoveCatalogItemParams
            xmlns="http://www.vmware.com/vcloud/v1.5">
            <Source
                href="$($catalogItem.href)"
                id="$($catalogItem.id)"
                type="$($catalogItem.type)"
                name="$($catalogItem.name)"/>
        </CopyOrMoveCatalogItemParams>
"@

            $copyItemToStagingCatalogResponse = Invoke-RestMethod -Uri $stagingCatalogCopyUrl -Method Post -Headers $Headers -ContentType "application/vnd.vmware.vcloud.copyOrMoveCatalogItemParams+xml" -Body $copyItemToStagingCatalogBody
            $copyItemToStagingCatalogTask = $copyItemToStagingCatalogResponse.Task.href
            $copyItemToStagingCatalogTaskStatus = (Invoke-RestMethod -Uri $copyItemToStagingCatalogTask -Method Get -Headers $Headers).Task.status
            while ($copyItemToStagingCatalogTaskStatus -like "running" -or $copyItemToStagingCatalogTaskStatus -like "queued") {
                Start-Sleep -Seconds 10
                $copyItemToStagingCatalogTaskStatus = (Invoke-RestMethod -Uri $copyItemToStagingCatalogTask -Method Get -Headers $Headers).Task.status
                $copyItemToStagingCatalogTaskProgress = (Invoke-RestMethod -Uri $copyItemToStagingCatalogTask -Method Get -Headers $Headers).Task.progress
                if ($copyItemToStagingCatalogTaskProgress) {
                    Write-Host "Copy task progress is $copyItemToStagingCatalogTaskProgress%."
                } else {
                    Write-Host "Copy task is in progress."
                }
            }

            if ($copyItemToStagingCatalogTaskStatus -like "success") {
                Write-Host "Catalog item copied successfully, moving it to $($destinationCatalog.name)." -ForegroundColor Green
                $copiedItemDetails = (Invoke-RestMethod -Uri $stagingCatalog.href -Method Get -Headers $headers).Catalog.CatalogItems.CatalogItem | ? {$_.name -like $catalogItem.name}
                if ($copiedItemDetails) {
                    $moveItemToDestinationCatalogBody = @"
                <CopyOrMoveCatalogItemParams
                    xmlns="http://www.vmware.com/vcloud/v1.5">
                    <Source
                        href="$($copiedItemDetails.href)"
                        id="$($copiedItemDetails.id)"
                        type="$($copiedItemDetails.type)"
                        name="$($copiedItemDetails.name)"/>
                </CopyOrMoveCatalogItemParams>
"@
                    $moveItemToDestinationCatalogResponse = Invoke-RestMethod -Uri $destinationCatalogMoveUrl -Method Post -Headers $Headers -ContentType "application/vnd.vmware.vcloud.copyOrMoveCatalogItemParams+xml" -Body $moveItemToDestinationCatalogBody
                    $moveItemToDestinationCatalogTask = $moveItemToDestinationCatalogResponse.Task.href
                    $moveItemToDestinationCatalogTaskStatus = (Invoke-RestMethod -Uri $moveItemToDestinationCatalogTask -Method Get -Headers $Headers).Task.status
                    while ($moveItemToDestinationCatalogTaskStatus -like "running" -or $moveItemToDestinationCatalogTaskStatus -like "queued") {
                        Start-Sleep -Seconds 10
                        $moveItemToDestinationCatalogTaskStatus = (Invoke-RestMethod -Uri $moveItemToDestinationCatalogTask -Method Get -Headers $Headers).Task.status
                        $moveItemToDestinationCatalogTaskProgress = (Invoke-RestMethod -Uri $moveItemToDestinationCatalogTask -Method Get -Headers $Headers).Task.progress
                        if ($moveItemToDestinationCatalogTaskProgress) {
                            Write-Host "Move task progress is $moveItemToDestinationCatalogTaskProgress%."
                        } else {
                            Write-Host "Move task is in progress."
                        }
                    }

                    if ($moveItemToDestinationCatalogTaskStatus -like "success") {
                        Write-Host "Catalog item moved successfully." -ForegroundColor Green
                    } else {
                        Write-Host "Failed to move catalog item." -ForegroundColor Green
                    }
                } else {
                    Write-Host "Failed to fetch catalog item details from $($stagingCatalog.name)."
                }
            } else {
                Write-Host "Failed to copy catalog item." -ForegroundColor Red
            }
        } else {
            Write-Host "$($catalogItem.name) already present in $($destinationCatalog.name), skipping copy." -ForegroundColor Green
        }
    }
}

$vcdHeaders = Login-Vcloud -Vcloud $vcloudHost -OrgName $vcloudOrg -UserName $vcloudUserName -Password $vcloudPassword
if ($vcdHeaders) {
    Move-ItemsToCatalog -Vcloud $vcloudHost -OrgName $vcloudOrg -Headers $vcdHeaders -SourceCatalogName $sourceCatalogName -StagingCatalogName $stagingCatalogName -DestinationCatalogName $destinationCatalogName
} else {
    Write-Host "Failed to log in to vCloud Director Org $vcloudOrg using username $vcloudUserName." -ForegroundColor Red
}