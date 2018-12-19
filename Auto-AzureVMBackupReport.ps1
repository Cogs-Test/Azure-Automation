<#
    .DESCRIPTION
        This report outputs a backup status report for all virtual machines within Azure.

    .NOTES
        AUTHOR: J. Michael Taylor <jay.taylor@va.gov | michael.taylor@cognosante.com>
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


function Set-AzureLogin{
    
    $connectionName = "AzureRunAsConnection"
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

function Get-FileName ([String]$Report_Name){    
    
    $date=Get-Date -UFormat "%Y%m%d"

    $file_name = $Report_Name + "-" + $date + ".csv"
    
    return $file_name
}

function Invoke-AzureSubscriptionLoop{
    
    Set-AzureLogin

    # Fetch current working directory 
    $Report_Name = Get-FileName -Report_Name "AzureVMReport"

    # Fetching subscription list
    $subscription_list = Get-AzureRmSubscription
    
    # Fetching the IaaS inventory list for each subscription
    foreach($subscription_list_iterator in $subscription_list){

        Get-AzureVMBackupReport -subscription_ID $subscription_list_iterator.id -subscription_name $subscription_list_iterator.Name -Report_Name $Report_Name
       
    }
}

function Get-AzureVMBackupReport ([String]$subscription_ID,[String]$subscription_name,[String]$Report_Name) {

    $subscription_ID=$subscription_ID.Trim()
    $subscription_name=$subscription_name.Trim()

    # Selecting the subscription
    Select-AzureRmSubscription -Subscription $subscription_ID

    $resource_groups = Get-AzureRmResourceGroup

    #Iterate through resource groups
    foreach($resource_group_iterator in $resource_groups){
        
        # Initialize Objects
        $azure_VM_array = $null
        $azure_VM_array = @()
        
        $azureVMDetails = Get-AzureRmVM -ResourceGroupName $resource_group_iterator.ResourceGroupName -Verbose 
        
        #Iterate through VMs
        foreach($vm_iterator in $azureVMDetails){
            
            $virtual_machine_backup = [PSCustomObject]@{
                SubscriptionName = ""
                ResourceGroupName = ""
                VMName = ""
                Location = ""
                VMSize = ""
                OSDisk = ""
            }

            $virtual_machine_backup.SubscriptionName = $subscription_name
            $virtual_machine_backup.ResourceGroupName = $resource_group_iterator.ResourceGroupName
            $virtual_machine_backup.VMName = $vm_iterator.Name
            $virtual_machine_backup.Location = $vm_iterator.Location
            $virtual_machine_backup.VMSize = $vm_iterator.HardwareProfile.VmSize
            $virtual_machine_backup.OSDisk = $vm_iterator.StorageProfile.OsDisk.OsType

            $azure_VM_array += $virtual_machine_backup

        }
        #$azure_VM_array | Export-Csv "AzureVMReport.csv" -NoTypeInformation -Append

        # Initialize Objects
        $azure_Backup_array = $null
        $azure_Backup_array = @()
        $recovery_vault_list = Get-AzureRmRecoveryServicesVault -ResourceGroupName $resource_group_iterator.ResourceGroupName

        foreach($rsv_iterator in $recovery_vault_list) {

            Set-AzureRmRecoveryServicesVaultContext -Vault $rsv_iterator
                
            $container_list = Get-AzureRmRecoveryServicesBackupContainer -ContainerType AzureVM 

            foreach($container_list_iterator in $container_list){

                $backup_item = Get-AzureRmRecoveryServicesBackupItem -Container $container_list_iterator -WorkloadType "AzureVM"
                
                foreach($backup in $backup_item) {

                    $backup_object = [PSCustomObject]@{
                        SubscriptionName = ""
                        ResourceGroupName = ""
                        RecoveryVault = ""
                        FriendlyName = ""
                        ProtectionStatus = ""
                        ProtectionState = ""
                        LastBackupTime = ""
                        ProtectionPolicyName = ""
                        LatestRecoveryPoint = ""
                    }

                    $backup_object.SubscriptionName = $subscription_name
                    $backup_object.ResourceGroupName = $resource_group_iterator.ResourceGroupName
                    $backup_object.RecoveryVault = $rsv_iterator.Name
                    $backup_object.FriendlyName = $container_list_iterator.FriendlyName
                    $backup_object.ProtectionStatus = $backup.ProtectionStatus
                    $backup_object.ProtectionState = $backup.LastBackupStatus
                    $backup_object.LastBackupTime = $backup.LastBackupTime
                    $backup_object.ProtectionPolicyName = $backup.ProtectionPolicyName
                    $backup_object.LatestRecoveryPoint = $backup.LatestRecoveryPoint
                    
                    if(-Not($azure_Backup_array.FriendlyName -contains $backup_object.FriendlyName)) {
                        $azure_Backup_array += $backup_object
                    }
                }

            }
           
        }
       
        Write-Output ("Building VM Backup Report for RG: " + $resource_group_iterator.ResourceGroupName  + " SUB: " + $subscription_name)

        # Initialize Object
        $export_array = $null
        $export_array = @()

        foreach($vm_detail in $azure_VM_array) {

            $export_object = [PSCustomObject]@{
                SubscriptionName = ""
                ResourceGroupName = ""
                VMName = ""
                Location = ""
                VMSize = ""
                OSDisk = ""
                RecoveryVault = ""
                ProtectionStatus = ""
                ProtectionState = ""
                LastBackupTime = ""
                ProtectionPolicyName = ""
                LatestRecoveryPoint = ""
            }

            $backup = $azure_Backup_array | ?{($_.FriendlyName.Trim() -eq $vm_detail.VMName.Trim())}
            $export_object.SubscriptionName = $vm_detail.SubscriptionName
            $export_object.ResourceGroupName = $vm_detail.ResourceGroupName
            $export_object.VMName = $vm_detail.VMName
            $export_object.Location = $vm_detail.Location
            $export_object.VMSize = $vm_detail.VMSize
            $export_object.OSDisk = $vm_detail.OSDisk
            $export_object.RecoveryVault = $backup.RecoveryVault
            $export_object.ProtectionStatus = $backup.ProtectionStatus
            $export_object.ProtectionState = $backup.ProtectionState
            $export_object.LastBackupTime = $backup.LastBackupTime
            $export_object.ProtectionPolicyName = $backup.ProtectionPolicyName
            $export_object.LatestRecoveryPoint = $backup.LatestRecoveryPoint

            $export_array += $export_object

        }
        Write-Output ("Writing to: " + $Report_Name)
        $export_array | Export-Csv $Report_Name -NoTypeInformation -Append
            
    }

    # Connect to Storage Account
    Set-AzureRmCurrentStorageAccount `
        -StorageAccountName $StorageAccountName `
        -ResourceGroupName $StorageAccountResourceGroup

    # Transfer output file to Blob storage
    Set-AzureStorageBlobContent `
        -Container $StorageContainerName `
        -File $Report_Name `
        -Blob $Report_Name `
        -Force
    
}

Invoke-AzureSubscriptionLoop



