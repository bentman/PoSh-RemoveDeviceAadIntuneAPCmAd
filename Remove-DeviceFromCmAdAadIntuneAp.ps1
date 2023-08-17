<#
.SYNOPSIS
    Deletes device records in AD / AAD / Intune / Autopilot / ConfigMgr, primarily beneficial for Autopilot test deployments.
.DESCRIPTION
    Depending on the provided parameters, this script facilitates operations related to Active Directory, ConfigMgr, Azure AD, Intune, and Autopilot. 
    The script checks for prerequisites, imports the necessary modules, and executes the relevant operations.
.PARAMETER
    serialNumber
    The serial number of the device to be processed. This parameter is mandatory and is used to locate the device across all services.
.REQUIREMENTS
    - General:
        * For all scenarios, the user account must have the required permissions to read and delete device records.
        * Necessary Microsoft Graph modules will be installed for the user if they aren't present.
    - Active Directory (AD):
        * The host workstation needs to be joined to the domain.
        * The host workstation should be able to communicate with a domain controller.
    - Configuration Manager (ConfigMgr):
        * ConfigMgr PowerShell module should be installed on the host workstation.
    - Azure Active Directory (Azure AD), Intune, and Autopilot:
        * The Microsoft Graph PowerShell enterprise application with App ID 14d82eec-204b-4c2f-b7e8-296a70dab67e is required.
        * The following permissions, granted with admin consent, are essential:
            - Directory.AccessAsUser.All (for Azure AD)
            - DeviceManagementManagedDevices.ReadWrite.All (for Intune)
            - DeviceManagementServiceConfig.ReadWrite.All (for Autopilot)
.ASSUMPTIONS
    * Devices in ConfigMgr and Intune have unique serial numbers and names, respectively. If multiple devices are found with the same identifier, the script will exit with a warning.
.OUTPUTS
    * Hosted outputs, typically in color-coded (green for success, red for failure) format for easy identification.
    * Error messages and warnings generated based on encountered issues.
.DEPENDENCIES
    * ActiveDirectory module (for AD operations)
    * Configuration Manager PowerShell module (for ConfigMgr operations)
    * Microsoft.Graph modules (for AAD, Intune, and Autopilot operations)
.EXAMPLE
    .\Remove-DeviceCmAdAadIntuneAp.ps1 -serialNumber "XYZ123" -All
    This will locate and remove the device with the provided serial number across all platforms/services.
.EXAMPLE
    .\Remove-DeviceCmAdAadIntuneAp.ps1 -serialNumber "XYZ123" -ConfigMgr
    This will locate and remove the device with the provided serial number from ConfigMgr.
.EXAMPLE
    .\Remove-DeviceCmAdAadIntuneAp.ps1 -serialNumber "XYZ123" -ConfigMgr -AD
    This will locate and remove the device with the provided serial number from both ConfigMgr and Active Directory.
.CREDIT
    Original script sourced from: https://gist.github.com/SMSAgentSoftware/27ff318f3973b97ca6b5cb99e8c93293
    [OpenAI's ChatGPT](https://chat.openai.com/) was employed to enhance the original script.
.NOTES
    Version: 1.0
    Creation Date: 2023-08-17
    Copyright (c) 2023 https://github.com/bentman
    https://github.com/bentman/Use-TsToExcel
#>
[CmdletBinding(DefaultParameterSetName='All')] 
param (
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,ParameterSetName='All')]
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true, ParameterSetName='Individual')] [string]$serialNumber,
    [Parameter(ParameterSetName='All')] [switch]$All,
    [Parameter(ParameterSetName='Individual')] [switch]$ConfigMgr,
    [Parameter(ParameterSetName='Individual')] [switch]$AD,
    [Parameter(ParameterSetName='Individual')] [switch]$AAD,
    [Parameter(ParameterSetName='Individual')] [switch]$Intune,
    [Parameter(ParameterSetName='Individual')] [switch]$Autopilot
)
# Change location to system drive
Set-Location $env:SystemDrive
# Load Configuration Manager module
if ($PSBoundParameters.ContainsKey("ConfigMgr") -or $PSBoundParameters.ContainsKey("All")) {
    $SMSEnvVar = [System.Environment]::GetEnvironmentVariable('SMS_ADMIN_UI_PATH') 
    if ($SMSEnvVar) {
        $ModulePath = $SMSEnvVar.Replace('i386','ConfigurationManager.psd1') 
        if ([System.IO.File]::Exists($ModulePath)) {
            try {
                Import-Module $ModulePath -ErrorAction Stop
            } catch {
                throw "Failed to import ConfigMgr module: $($_.Exception.Message)"
            }
        } else {
            throw "ConfigMgr module not found"
        }
    } else {
        throw "SMS_ADMIN_UI_PATH environment variable not found"
    }
}
# Check if we should be importing modules
$shouldImportModules = $PSBoundParameters.ContainsKey("AAD") -or 
                       $PSBoundParameters.ContainsKey("Intune") -or 
                       $PSBoundParameters.ContainsKey("Autopilot") -or 
                       $PSBoundParameters.ContainsKey("All")
#region Modules
if ($shouldImportModules) {
    Write-Host "Importing modules"
    # Ensure the NuGet provider is available, as it's required for module installations
    $provider = Get-PackageProvider NuGet -ErrorAction Ignore
    if (-not $provider) {
        Write-Host "Installing provider NuGet..." -NoNewline
        try {
            # Attempt to bootstrap (install) the NuGet provider with all dependencies
            Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -Force -ErrorAction Stop
            Write-Host "Success" -ForegroundColor Green
        } catch {
            Write-Host "Failed" -ForegroundColor Red
            throw $_.Exception.Message
        }
    }
    function Invoke-ModuleInstallOrImport($moduleName) {
        # Check if module is imported - if not, attempt to install and import it.
        $module = Import-Module $moduleName -PassThru -ErrorAction Ignore
        if (-not $module) {
            Write-Host "Installing module $moduleName..." -NoNewline
            try {
                # Attempt to install the module for the current user
                Install-Module $moduleName -Scope CurrentUser -Force -ErrorAction Stop
                Write-Host "Success" -ForegroundColor Green
            } catch {
                Write-Host "Failed" -ForegroundColor Red
                throw $_.Exception.Message
            } 
        }
    }
    # List of modules to ensure they're imported or installed
    $modulesToInstallOrImport = @(
        "Microsoft.Graph.Identity.DirectoryManagement",
        "Microsoft.Graph.DeviceManagement",
        "Microsoft.Graph.DeviceManagement.Enrollment"
    )
    # Process each module in the list
    foreach ($module in $modulesToInstallOrImport) {Invoke-ModuleInstallOrImport $module}
} # endregion Modules 

#region Authentication
# Check if Azure AD, Intune, Autopilot, or All flags have been provided to determine the need for authentication
$requiresAuthentication = $PSBoundParameters.ContainsKey("AAD") -or 
                          $PSBoundParameters.ContainsKey("Intune") -or 
                          $PSBoundParameters.ContainsKey("Autopilot") -or 
                          $PSBoundParameters.ContainsKey("All")
if ($requiresAuthentication) {
    Write-Host "Authenticating..." -NoNewline
    try { # Connect to Microsoft Graph using necessary scopes
        $null = Connect-MgGraph -Scopes "Directory.AccessAsUser.All",
                                 "DeviceManagementManagedDevices.ReadWrite.All",
                                 "DeviceManagementServiceConfig.ReadWrite.All" -ErrorAction Stop
        # Uncomment the below line if the above set of scopes aren't needed
        # $null = Connect-MgGraph -Scopes "Directory.AccessAsUser.All","DeviceManagementServiceConfig.ReadWrite.All" -ErrorAction Stop
        Write-Host "Success" -ForegroundColor Green
    } catch {
        Write-Host "Failed" -ForegroundColor Red
        throw $_.Exception.Message
    }
} #endregion Authentication

#region ConfigMgr
if ($PSBoundParameters.ContainsKey("ConfigMgr") -or $PSBoundParameters.ContainsKey("All")) {
    # Attempt to locate the device in ConfigMgr using serial number
    Write-Host "Locating device in" -NoNewline
    Write-Host " ConfigMgr" -ForegroundColor Magenta -NoNewline
    Write-Host "..." -NoNewline
    try {
        $SiteCode = (Get-PSDrive -PSProvider CMSITE -ErrorAction Stop).Name
        Push-Location "$($SiteCode):" -ErrorAction Stop
        # Getting the computer name associated with the serial number from ConfigMgr
        [array]$ConfigMgrDevices = Get-CMDevice | Where-Object { 
            (Get-CMDeviceHardwareInventory -ResourceId $_.ResourceID | 
            Select-Object -ExpandProperty SMS_G_System_COMPUTER_SYSTEM_PRODUCT).Version -eq $serialNumber 
        } -ErrorAction Stop
        # Storing the associated computer name for future use in other regions
        $global:ComputerName = $ConfigMgrDevices[0].Name
        Write-Host "Success" -ForegroundColor Green
    } catch {
        Write-Host "Fail" -ForegroundColor Red
        Write-Error "$($_.Exception.Message)"
        $LocateInConfigMgrFailure = $true
    }
    # If successfully located, attempt removal from ConfigMgr
    if (!$LocateInConfigMgrFailure) {
        if ($ConfigMgrDevices.Count -eq 1) {
            $ConfigMgrDevice = $ConfigMgrDevices[0]
            Write-Host "  ResourceID: $($ConfigMgrDevice.ResourceID)"
            Write-Host "  SMSID: $($ConfigMgrDevice.SMSID)"
            Write-Host "  UserDomainName: $($ConfigMgrDevice.UserDomainName)"
            Write-Host "  ComputerName: $global:ComputerName"
            Write-Host "Removing device from" -NoNewline
            Write-Host " ConfigMgr" -ForegroundColor Magenta -NoNewline
            Write-Host "..." -NoNewline
            try {
                Remove-CMDevice -InputObject $ConfigMgrDevice -Force -ErrorAction Stop
                Write-Host "Success" -ForegroundColor Green
            } catch {
                Write-Host "Fail" -ForegroundColor Red
                Write-Error "$($_.Exception.Message)"
            }
        } elseif ($ConfigMgrDevices.Count -gt 1) {
            Write-Host "Fail" -ForegroundColor Red
            Write-Warning "Multiple devices found in ConfigMgr with the same serial number. Serial number must be unique." 
            Return
        } else {
            Write-Host "Fail" -ForegroundColor Red
            Write-Warning "Device not found in ConfigMgr using the provided serial number."    
        }
    }
    Pop-Location
} #endregion ConfigMgr

#region AD
if ($PSBoundParameters.ContainsKey("AD") -or $PSBoundParameters.ContainsKey("All"))
{
    try
    {
        Write-host "Locating device in " -NoNewline
        Write-host "Active Directory" -ForegroundColor Blue -NoNewline
        Write-Host "..." -NoNewline
        $Searcher = [ADSISearcher]::new()
        $Searcher.Filter = "(sAMAccountName=$ComputerName`$)"
        [void]$Searcher.PropertiesToLoad.Add("distinguishedName")
        $ComputerAccount = $Searcher.FindOne()
        if ($ComputerAccount)
        {
            Write-host "Success" -ForegroundColor Green
            Write-Host "Removing device from" -NoNewline
            Write-Host "Active Directory" -NoNewline -ForegroundColor Blue
            Write-Host "..." -NoNewline
            $DirectoryEntry = $ComputerAccount.GetDirectoryEntry()
            $result = $DirectoryEntry.DeleteTree()
            Write-Host "Success" -ForegroundColor Green
        }
        Else
        {
            Write-host "Fail" -ForegroundColor Red
            Write-Warning "Device not found in Active Directory"  
        }
    }
    catch
    {
        Write-host "Fail" -ForegroundColor Red
        Write-Error "$($_.Exception.Message)"
    }
} #endregion

#region AD
if ($PSBoundParameters.ContainsKey("AD") -or $PSBoundParameters.ContainsKey("All")) {
    try {
        Write-Host "Locating device in" -NoNewline
        Write-Host " Active Directory" -ForegroundColor Blue -NoNewline
        Write-Host "..." -NoNewline
        $Searcher = [ADSISearcher]::new()
        $Searcher.Filter = "(sAMAccountName=$ComputerName`$)"
        [void]$Searcher.PropertiesToLoad.Add("distinguishedName")
        $ComputerAccount = $Searcher.FindOne()
        if ($ComputerAccount) {
            Write-Host "Success" -ForegroundColor Green
            Write-Host "Removing device from" -NoNewline
            Write-Host " Active Directory" -ForegroundColor Blue -NoNewline
            Write-Host "..." -NoNewline
            $DirectoryEntry = $ComputerAccount.GetDirectoryEntry()
            $result = $DirectoryEntry.DeleteTree()
            Write-Host "Success" -ForegroundColor Green
        } else {
            Write-Host "Fail" -ForegroundColor Red
            Write-Warning "Device not found in Active Directory"
        }
    } catch {
        Write-Host "Fail" -ForegroundColor Red
        Write-Error "$($_.Exception.Message)"
    }
} #endregion AD

#region Intune
if ($PSBoundParameters.ContainsKey("Intune") -or $PSBoundParameters.ContainsKey("Autopilot") -or $PSBoundParameters.ContainsKey("All")) {
    Write-Host "Locating device in" -NoNewline
    Write-Host " Intune" -NoNewline -ForegroundColor Cyan
    Write-Host "..." -NoNewline
    try {
        $IntuneDevice = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$ComputerName' or hardwareSerialNumber eq '$serialNumber'" -ErrorAction Stop
    } catch {
        Write-Host "Fail" -ForegroundColor Red
        Write-Error "$($_.Exception.Message)"
        $LocateInIntuneFailure = $true
    }
    if (!$LocateInIntuneFailure) {
        if ($IntuneDevice.Count -eq 1) {
            Write-Host "Success" -ForegroundColor Green
            Write-Host "  DeviceName: $($IntuneDevice.DeviceName)"
            Write-Host "  ObjectId: $($IntuneDevice.Id)"
            Write-Host "  AzureAdDeviceId: $($IntuneDevice.AzureAdDeviceId)"
            Write-Host "Removing device from" -NoNewline
            Write-Host " Intune" -NoNewline -ForegroundColor Cyan
            Write-Host "..." -NoNewline
            try {
                $result = Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $IntuneDevice.Id -PassThru -ErrorAction Stop
                if ($result -eq $true) {Write-Host "Success" -ForegroundColor Green
                } else {Write-Host "Fail" -ForegroundColor Red}
            } catch {
                Write-Host "Fail" -ForegroundColor Red
                Write-Error "$($_.Exception.Message)"
            }           
        } elseif ($IntuneDevice.Count -gt 1) {
            Write-Host "Fail" -ForegroundColor Red
            Write-Warning "Multiple devices found in Intune with the same device name or serial number. Ensure uniqueness." 
        } else {
            Write-Host "Fail" -ForegroundColor Red
            Write-Warning "Device not found in Azure AD"    
        }
    }
} #endregion Intune

#region Autopilot
if (($PSBoundParameters.ContainsKey("Autopilot") -or $PSBoundParameters.ContainsKey("All")) -and $IntuneDevice.Count -eq 1) {
    Write-Host "Locating device in" -NoNewline
    Write-Host " Windows Autopilot" -NoNewline -ForegroundColor Cyan
    Write-Host "..." -NoNewline
    try {
        $AutopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "deviceName eq '$ComputerName' or contains(serialNumber,'$serialNumber')" -ErrorAction Stop
        #$Response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$SerialNumber')" -ErrorAction Stop
    } catch {
        Write-Host "Fail" -ForegroundColor Red
        Write-Error "$($_.Exception.Message)"
        $LocateInAutopilotFailure = $true
    }
    if (!$LocateInAutopilotFailure) {
        if ($AutopilotDevice.Count -eq 1) {
            Write-Host "Success" -ForegroundColor Green
            Write-Host "  SerialNumber: $($AutopilotDevice.SerialNumber)"
            Write-Host "  Id: $($AutopilotDevice.Id)"
            Write-Host "  ManagedDeviceId: $($AutopilotDevice.ManagedDeviceId)"
            Write-Host "  Model: $($AutopilotDevice.Model)"
            Write-Host "  GroupTag: $($AutopilotDevice.GroupTag)"
            Write-Host "Removing device from" -NoNewline
            Write-Host " Windows Autopilot" -NoNewline -ForegroundColor Cyan
            Write-Host "..." -NoNewline
            try {
                $result = Remove-MgDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $AutopilotDevice.Id -PassThru -ErrorAction Stop
                if ($result -eq $true) {Write-Host "Success" -ForegroundColor Green
                } else {Write-Host "Fail" -ForegroundColor Red}
            } catch {
                Write-Host "Fail" -ForegroundColor Red
                Write-Error "$($_.Exception.Message)"
            }           
        } elseif ($AutopilotDevice.Count -gt 1) {
            Write-Host "Fail" -ForegroundColor Red
            Write-Warning "Multiple devices found in Windows Autopilot with the same device name or serial number. Ensure uniqueness." 
            Return
        } else {
            Write-Host "Fail" -ForegroundColor Red
            Write-Warning "Device not found in Windows Autopilot"    
        }
    }
} #endregion Autopilot

Set-Location $env:SystemDrive
if ($PSBoundParameters.ContainsKey("AAD") -or 
    $PSBoundParameters.ContainsKey("Intune") -or 
    $PSBoundParameters.ContainsKey("Autopilot") -or 
    $PSBoundParameters.ContainsKey("All")) {
        $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
}