<#
    .DESCRIPTION
        This report is intended for use in Azure Automation. It outputs a report that contains Tags for all resources and resource 
        groups in Azure. The output file is written to temporary storage and transferred to a storage account. 
        NULL tag = No tags for this resource.

    .NOTES
        AUTHOR: Michael Taylor <michael.taylor@cognosante.com>
        LASTEDIT: 8/24/2018
#>

Param (
    [Parameter (Mandatory=$true)]
    [STRING] $StorageAccountName,
    [Parameter (Mandatory=$true)]
    [STRING] $StorageAccountResourceGroup,
    [Parameter (Mandatory=$true)]
    [STRING] $StorageContainerName
)

$connectionName = "AzureRunAsConnection"

function Set-CogAzureLogin{
    
    try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         
    Write-Output $servicePrincipalConnection

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | Out-Null 
        #-EnvironmentName AzureUSGovernment | Out-Null 
    Write-Output "Logged in."
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

    
}

function Get-CogFileName ([String]$Report_Name){    
    
    $date=Get-Date -UFormat "%Y%m%d"

    $file_name = $Report_Name + "-" + $date + ".csv"
    
    return $file_name
}

function Invoke-AzureSubscriptionLoop{
    
    Set-CogAzureLogin
    
    
    # Fetch current working directory 
    $Report_Name = Get-CogFileName -Report_Name "AzureTagsReport"
    Write-Output ("Writing report " + $Report_Name)

    # Fetching subscription list
    $subscription_list = Get-AzureRmSubscription
    
    Write-Output $subscription_list

    # Fetching the IaaS inventory list for each subscription
    foreach($subscription in $subscription_list){

        Write-Output ("Subscription Name: " + $subscription.SubscriptionName)

        try {

            #Selecting the Azure Subscription
            Select-AzureRmSubscription -SubscriptionName $subscription.SubscriptionName | Out-Null 
            #Set-AzureRmCurrentStorageAccount -StorageAccountName "cs2b0db20fd045ex41bbxbe6"
            
            $resource_groups = Get-AzureRmResourceGroup 
            
            $export_array = $null
            $export_array = @()
            #Iterate through resource groups
            foreach($resource_group in $resource_groups){
                
                Write-Output ("Resource Group " + $resource_group.ResourceGroupName)
                #Get Resource Group Tags
                $rg_tags = (Get-AzureRmResourceGroup -Name $resource_group.ResourceGroupName)
                $Tags = $rg_tags.Tags
                #Checking if tags is null or has value
                if($Tags -ne $null){
                    
                    $Tags.GetEnumerator() | % { 
                        $details = @{            
                            ResourceId = $resource_group.ResourceId
                            Name = $resource_group.ResourceGroupName
                            ResourceType = "Resource-Group"
                            ResourceGroupName =$resource_group.ResourceGroupName
                            Location = $resource_group.Location
                            SubscriptionName = $subscription.SubscriptionName 
                            Tag_Key = $_.Key
                            Tag_Value = $_.Value
                            }
                         $export_array += New-Object PSObject -Property $details
                         }
                                        

                }else{

                    $TagsAsString = "NULL"
                    $details = @{            
                        ResourceId = $resource_group.ResourceId
                        Name = $resource_group.ResourceGroupName
                        ResourceType = "Resource-Group"
                        ResourceGroupName =$resource_group.ResourceGroupName
                        Location = $resource_group.Location
                        SubscriptionName = $subscription.SubscriptionName 
                        Tag_Key = "NULL"
                        Tag_Value = "NULL"
                    }                           
                $export_array += New-Object PSObject -Property $details 
                }
            }

            #Getting all Azure Resources
            $resource_list = Get-AzureRmResource
            
            #Declaring Variables
            $TagsAsString = ""

            foreach($resource in $resource_list){
               
                #Fetching Tags
                $Tags = $resource.Tags
    
                #Checking if tags is null or has value
                if($Tags -ne $null){
                    
                    $Tags.GetEnumerator() | % { 
                        $details = @{            
                            ResourceId = $resource.ResourceId
                            Name = $resource.Name
                            ResourceType = $resource.ResourceType
                            ResourceGroupName =$resource.ResourceGroupName
                            Location = $resource.Location
                            SubscriptionName = $subscription.SubscriptionName 
                            Tag_Key = $_.Key
                            Tag_Value = $_.Value
                            }
                         $export_array += New-Object PSObject -Property $details
                         }
                                        

                }else{

                    $TagsAsString = "NULL"
                    $details = @{            
                    ResourceId = $resource.ResourceId
                    Name = $resource.Name
                    ResourceType = $resource.ResourceType
                    ResourceGroupName =$resource.ResourceGroupName
                    Location = $resource.Location
                    SubscriptionName = $subscription.SubscriptionName 
                    Tag_Key = "NULL"
                    Tag_Value = "NULL"
                    }                           
                $export_array += New-Object PSObject -Property $details 
                }
            }

            #Generating Output
            Write-Output ("Writing to: " + $Report_Name)
            #write $export_array
            $export_array | Export-Csv $Report_Name -NoTypeInformation -Append
           
        }
        catch [system.exception]{

	        Write-Output "Error in generating report: $($_.Exception.Message) "
            Write-Output "Error Details are: "
            Write-Output $Error[0].ToString()
	        Exit $ERRORLEVEL
        }
    }     
    Set-AzureRmCurrentStorageAccount -StorageAccountName $StorageAccountName -ResourceGroupName $StorageAccountResourceGroup
    Set-AzureStorageBlobContent -Container $StorageContainerName -File $Report_Name -Blob $Report_Name -Force
}

Invoke-AzureSubscriptionLoop
