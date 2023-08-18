<#
.SYNOPSIS
    Deletes device records in AAD / Intune / Autopilot / ConfigMgr / AD, useful for Autopilot test deployments.
.DESCRIPTION
    This script handles device removal across various platforms.
.PARAMETERS
    -serialNumber
        Mandatory for all platforms except AD. Used to locate devices.
    -computerName
        Used for AD operations. Needed if the serialNumber doesn't identify a device in ConfigMgr.
    -All
        Removes devices from all platforms/services using either the serialNumber or computerName.
    -AAD
        Deletes the device from Azure AD.
    -Intune
        Deletes the device from Intune.
    -Autopilot
        Deletes the device from Autopilot.
    -ConfigMgr
        Deletes from ConfigMgr. If successful, retrieves the computerName for AD operations.
    -AD
        Deletes the device from Active Directory.
.REQUIREMENTS
    - General:
        * Appropriate permissions are necessary.
        * Microsoft Graph modules will be installed if missing.
    - Cloud Platforms (AAD, Intune, Autopilot):
        * Requires the Microsoft Graph PowerShell enterprise application.
        * Specific permissions are necessary with admin consent.
    - ConfigMgr:
        * ConfigMgr PowerShell module is required.
    - AD:
        * Workstation should be in the domain and able to communicate with the domain controller.
.ASSUMPTIONS
    * Devices in ConfigMgr and Intune have unique identifiers. The script warns and exits if conflicts arise.
.OUTPUTS
    * Outputs in color (green = success, red = failure).
    * Relevant error messages and warnings.
.DEPENDENCIES
    * ActiveDirectory module
    * ConfigMgr PowerShell module
    * Microsoft.Graph modules
.EXAMPLE
    For cloud-only removal in AzureAD, Intune, and Autopilot.
        .\Remove-DeviceFromAadIntuneApCmAd.ps1 -serialNumber "XYZ1234" -AAD -Intune -Autopilot
    For on-prem removal in ConfigMgr and AD.
        .\Remove-DeviceFromAadIntuneApCmAd.ps1 -serialNumber "XYZ1234" -ConfigMgr -AD
    For removal across all platforms.
        .\Remove-DeviceFromAadIntuneApCmAd.ps1 -serialNumber "XYZ1234" -All
    For AD-only removal.
        .\Remove-DeviceFromAadIntuneApCmAd.ps1 -computerName "HQO-XYZ1234" -AD
.CREDIT
    Original script sourced from: https://gist.github.com/SMSAgentSoftware/27ff318f3973b97ca6b5cb99e8c93293
    Enhanced with [OpenAI's ChatGPT](https://chat.openai.com/).
.NOTES
    Version: 1.0
    Creation Date: 2023-08-17
    Copyright (c) 2023 https://github.com/bentman
    https://github.com/bentman/Use-TsToExcel
#>

[CmdletBinding(DefaultParameterSetName='BySerialNumber')]
param (
    [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true, ParameterSetName='BySerialNumber')]
    [string]$serialNumber,
    [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true, ParameterSetName='ByComputerName')]
    [string]$computerName,
    [Parameter(ParameterSetName='BySerialNumber')] [Parameter(ParameterSetName='ByComputerName')] [switch]$All,
    [Parameter(ParameterSetName='BySerialNumber')] [Parameter(ParameterSetName='ByComputerName')] [switch]$AAD, 
    [Parameter(ParameterSetName='BySerialNumber')] [Parameter(ParameterSetName='ByComputerName')] [switch]$Intune,
    [Parameter(ParameterSetName='BySerialNumber')] [Parameter(ParameterSetName='ByComputerName')] [switch]$Autopilot,
    [Parameter(ParameterSetName='BySerialNumber')] [Parameter(ParameterSetName='ByComputerName')] [switch]$ConfigMgr,
    [Parameter(ParameterSetName='BySerialNumber')] [Parameter(ParameterSetName='ByComputerName')] [switch]$AD
)

# Change location to system drive
Set-Location $env:SystemDrive

#region ParameterValidation
if (-not $PSBoundParameters.ContainsKey('serialNumber') -and -not $PSBoundParameters.ContainsKey('computerName')) {
    Write-Error "Either -serialNumber or -computerName must be provided (not both)."
    exit
}
if ($PSBoundParameters.ContainsKey('All')) {
    $AAD = $true
    $Intune = $true
    $Autopilot = $true
    $ConfigMgr = $true
    $AD = $true
}
if ($AD -and $PSBoundParameters.ContainsKey('serialNumber')) {
    if (-not ($AAD -or $Intune -or $Autopilot -or $ConfigMgr)) {
        Write-Error "-AD with -serialNumber requires one of -AAD, -Intune, -Autopilot, or -ConfigMgr to derive computerName."
        exit
    }
}
#endregion ParameterValidation

#region EnsureModules
# Import ConfigMgr module if necessary
if ($PSBoundParameters.ContainsKey('ConfigMgr')) {
    Import-Module (Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1) -ErrorAction Stop
}
# Check if we should be importing cloud modules
$shouldImportModules = $PSBoundParameters.ContainsKey("AAD") -or 
                       $PSBoundParameters.ContainsKey("Intune") -or 
                       $PSBoundParameters.ContainsKey("Autopilot") -or 
                       $PSBoundParameters.ContainsKey("All")
if ($shouldImportModules) {
    Write-Host "Importing modules"
    $provider = Get-PackageProvider NuGet -ErrorAction Ignore
    if (-not $provider) {
        Write-Host "Installing package provider  NuGet..." -NoNewline
        try {
            Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies -Force -ErrorAction Stop
            Write-Host "Success" -ForegroundColor Green
        } catch {
            Write-Host "Failed" -ForegroundColor Red
            throw $_.Exception.Message
        }
    }
    $moduleNames = @(
        "Microsoft.Graph.Identity.DirectoryManagement",
        "Microsoft.Graph.DeviceManagement",
        "Microsoft.Graph.DeviceManagement.Enrollment"
    )
    foreach ($moduleName in $moduleNames) {
        $module = Get-Module -Name $moduleName -ListAvailable
        if (-not $module) {
            Write-Host "Installing module $moduleName..." -NoNewline
            try {
                Install-Module $moduleName -Scope CurrentUser -Force -ErrorAction Stop
                Write-Host "Success" -ForegroundColor Green
                Import-Module $moduleName -ErrorAction Stop
            } catch {
                Write-Host "Failed" -ForegroundColor Red
                throw $_.Exception.Message
            }
        } else {
            Import-Module $moduleName -ErrorAction Stop
        }
    }
} #endregion EnsureModules

#region AuthenticateCloud
$requiresAuthentication = $PSBoundParameters.ContainsKey('AAD') -or 
                          $PSBoundParameters.ContainsKey('Intune') -or 
                          $PSBoundParameters.ContainsKey('Autopilot') -or 
                          $PSBoundParameters.ContainsKey('All')
if ($requiresAuthentication) {
    Write-Host "Authenticating..."
    # Set authentication scopes
    $scopes = @('https://graph.microsoft.com/.default')
    $graphAppId = 'd1ddf0e4-d672-4dae-b554-9d5bdfd93547'
    Connect-MgGraph -ClientId $graphAppId -TenantId $env:TENANT_ID -CertificateThumbprint $env:THUMBPRINT -Scopes $scopes
} #endregion AuthenticateCloud

#region Autopilot
if (($PSBoundParameters.ContainsKey("Autopilot") -or $PSBoundParameters.ContainsKey("All")) -and $IntuneDevice.Count -eq 1) {
    Write-Host "Locating device in Windows Autopilot" -NoNewline
    Write-Host "..." -NoNewline -ForegroundColor Cyan
    # Determine the filter condition based on provided parameters
    if ($serialNumber -and $computerName) {
        $filterCondition = "deviceName eq '$computerName' or contains(serialNumber,'$serialNumber')"
    } elseif ($serialNumber) {
        $filterCondition = "contains(serialNumber,'$serialNumber')"
    } elseif ($computerName) {
        $filterCondition = "deviceName eq '$computerName'"
    } else {
        Write-Host " Fail" -ForegroundColor Red
        Write-Warning "Either serialNumber or computerName must be provided for Autopilot search"
        return
    }
    try {
        $AutopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter $filterCondition -ErrorAction Stop
    } catch {
        Write-Host " Fail" -ForegroundColor Red
        Write-Error "$($_.Exception.Message)"
        $LocateInAutopilotFailure = $true
    }
    if (!$LocateInAutopilotFailure) {
        if ($AutopilotDevice.Count -eq 1) {
            Write-Host " Success" -ForegroundColor Green
            Write-Host "  SerialNumber: $($AutopilotDevice.SerialNumber)"
            Write-Host "  ObjectId: $($AutopilotDevice.Id)"
            Write-Host "  ZtdId: $($AutopilotDevice.ZtdId)"
            Write-Host "Removing device from Autopilot" -NoNewline
            Write-Host "..." -NoNewline -ForegroundColor Cyan
            try {
                $result = Remove-MgDeviceManagementWindowsAutopilotDeviceIdentity -Id $AutopilotDevice.Id -PassThru -ErrorAction Stop
                if ($result -eq $true) {
                    Write-Host " Success" -ForegroundColor Green
                } else {
                    Write-Host " Fail" -ForegroundColor Red
                }
            } catch {
                Write-Host " Fail" -ForegroundColor Red
                Write-Error "$($_.Exception.Message)"
            }
        } elseif ($AutopilotDevice.Count -gt 1) {
            Write-Host " Fail" -ForegroundColor Red
            Write-Warning "Multiple devices found in Autopilot with the same device name or serial number. Ensure uniqueness."
        } else {
            Write-Host " Fail" -ForegroundColor Red
            Write-Warning "Device not found in Autopilot"
        }
    }
} #endregion Autopilot

#region Intune
if ($PSBoundParameters.ContainsKey("Intune") -or $PSBoundParameters.ContainsKey("Autopilot") -or $PSBoundParameters.ContainsKey("All")) {
    Write-Host "Locating device in Intune" -NoNewline
    Write-Host "..." -NoNewline -ForegroundColor Cyan
    # Determine the filter condition based on provided parameters
    if ($serialNumber -and $computerName) {
        $filterCondition = "deviceName eq '$computerName' or hardwareSerialNumber eq '$serialNumber'"
    } elseif ($serialNumber) {
        $filterCondition = "hardwareSerialNumber eq '$serialNumber'"
    } elseif ($computerName) {
        $filterCondition = "deviceName eq '$computerName'"
    } else {
        Write-Host " Fail" -ForegroundColor Red
        Write-Warning "Either serialNumber or computerName must be provided for Intune search"
        return
    }
    try {
        $IntuneDevice = Get-MgDeviceManagementManagedDevice -Filter $filterCondition -ErrorAction Stop
    } catch {
        Write-Host " Fail" -ForegroundColor Red
        Write-Error "$($_.Exception.Message)"
        $LocateInIntuneFailure = $true
    }
    if (!$LocateInIntuneFailure) {
        if ($IntuneDevice.Count -eq 1) {
            Write-Host " Success" -ForegroundColor Green
            Write-Host "  DeviceName: $($IntuneDevice.DeviceName)"
            Write-Host "  ObjectId: $($IntuneDevice.Id)"
            Write-Host "  AzureAdDeviceId: $($IntuneDevice.AzureAdDeviceId)"
            Write-Host "Removing device from Intune" -NoNewline
            Write-Host "..." -NoNewline -ForegroundColor Cyan
            try {
                $result = Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $IntuneDevice.Id -PassThru -ErrorAction Stop
                if ($result -eq $true) {
                    Write-Host " Success" -ForegroundColor Green
                } else {
                    Write-Host " Fail" -ForegroundColor Red
                }
            } catch {
                Write-Host " Fail" -ForegroundColor Red
                Write-Error "$($_.Exception.Message)"
            }           
        } elseif ($IntuneDevice.Count -gt 1) {
            Write-Host " Fail" -ForegroundColor Red
            Write-Warning "Multiple devices found in Intune with the same device name or serial number. Ensure uniqueness."
        } else {
            Write-Host " Fail" -ForegroundColor Red
            Write-Warning "Device not found in Intune"
        }
    }
} #endregion Intune

#region AAD
if ($PSBoundParameters.ContainsKey("AAD") -or $PSBoundParameters.ContainsKey("All")) {
    Write-Host "Locating device in Azure AD" -NoNewline
    Write-Host "..." -NoNewline -ForegroundColor Yellow
    # Logic to decide the search parameter based on what's provided
    if ($serialNumber) {
        $searchParameter = "serialNumber:$serialNumber"
    } elseif ($computerName) {
        $searchParameter = "displayName:$computerName"
    } else {
        Write-Host " Fail" -ForegroundColor Red
        Write-Warning "Either serialNumber or computerName must be provided for Azure AD search"
        return
    }
    try {
        $AADDevice = Get-MgDevice -Search $searchParameter -CountVariable CountVar -ConsistencyLevel eventual -ErrorAction Stop
    } catch {
        Write-Host " Fail" -ForegroundColor Red
        Write-Error "$($_.Exception.Message)"
        $LocateInAADFailure = $true
    }
    if ($LocateInAADFailure -ne $true) {
        if ($AADDevice.Count -eq 1) {
            Write-Host " Success" -ForegroundColor Green
            Write-Host "  DisplayName: $($AADDevice.DisplayName)"
            Write-Host "  ObjectId: $($AADDevice.Id)"
            Write-Host "  DeviceId: $($AADDevice.DeviceId)"
            Write-Host "Removing device from Azure AD" -NoNewline
            Write-Host "..." -NoNewline -ForegroundColor Yellow
            try {
                $Result = Remove-MgDevice -DeviceId $AADDevice.Id -PassThru -ErrorAction Stop
                if ($Result -eq $true) {
                    Write-Host " Success" -ForegroundColor Green
                } else {
                    Write-Host " Fail" -ForegroundColor Red
                }
            } catch {
                Write-Host " Fail" -ForegroundColor Red
                Write-Error "$($_.Exception.Message)"
            }
        } elseif ($AADDevice.Count -gt 1) {
            Write-Host " Fail" -ForegroundColor Red
            Write-Warning "Multiple devices found in Azure AD. The device display name must be unique."
        } else {
            Write-Host " Fail" -ForegroundColor Red
            Write-Warning "Device not found in Azure AD"
        }
    }
} #endregion AAD

#region ConfigMgr
if ($PSBoundParameters.ContainsKey("ConfigMgr") -or $PSBoundParameters.ContainsKey("All")) {
    # Attempt to locate the device in ConfigMgr using serial number
    Write-Host "Locating device in ConfigMgr" -NoNewline
    Write-Host "..." -NoNewline -ForegroundColor Magenta
    try {
        $SiteCode = (Get-PSDrive -PSProvider CMSITE -ErrorAction Stop).Name
        Push-Location "$($SiteCode):" -ErrorAction Stop
        # If serialNumber is provided, try to find the associated computer name
        if ($serialNumber) {
            # Getting the computer name associated with the serial number from ConfigMgr
            [array]$ConfigMgrDevices = Get-CMDevice | Where-Object { 
                (Get-CMDeviceHardwareInventory -ResourceId $_.ResourceID | 
                Select-Object -ExpandProperty SMS_G_System_COMPUTER_SYSTEM_PRODUCT).Version -eq $serialNumber 
            } -ErrorAction Stop
            # If a device is found in ConfigMgr for the serial number, set the computerName
            if ($ConfigMgrDevices.Count -eq 1) {
                $computerName = $ConfigMgrDevices[0].Name
            }
        }
        # If no computer name found or provided, throw an error
        if (-not $computerName) {
            Throw "Unable to locate a computer name associated with the provided serial number."
        }
        Write-Host " Success" -ForegroundColor Green
    } catch {
        Write-Host " Fail" -ForegroundColor Red
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
            Write-Host "  ComputerName: $computerName"
            Write-Host "Removing device from ConfigMgr" -NoNewline
            Write-Host "..." -NoNewline -ForegroundColor Magenta
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
}
#endregion ConfigMgr

#region AD
if ($PSBoundParameters.ContainsKey("AD") -or $PSBoundParameters.ContainsKey("All")) {
    # Ensure we have computerName
    if (-not $computerName) {
        Write-Warning "Computer name is not set, cannot proceed with AD lookup."
        return
    }
    Write-host "Locating device in Active Directory" -NoNewline
    Write-Host "..." -NoNewline -ForegroundColor Blue
    try {
        $Searcher = [ADSISearcher]::new()
        $Searcher.Filter = "(sAMAccountName=$computerName`$)"
        [void]$Searcher.PropertiesToLoad.Add("distinguishedName")
        $ComputerAccount = $Searcher.FindOne()
        if ($ComputerAccount) {
            Write-host " Success" -ForegroundColor Green
            Write-Host "Removing device from Active Directory" -NoNewline
            Write-Host "..." -NoNewline -ForegroundColor Blue
            # Optionally, you can add a confirmation prompt here
            # $confirmation = Read-Host "Are you sure you want to delete the computer account from AD? (Y/N)"
            # if ($confirmation -ne 'Y') {
            #    Write-Host " Operation aborted by user." -ForegroundColor Yellow
            #    return
            # }
            $DirectoryEntry = $ComputerAccount.GetDirectoryEntry()
            $result = $DirectoryEntry.DeleteTree()
            Write-Host " Success" -ForegroundColor Green
        } else {
            Write-host " Fail" -ForegroundColor Red
            Write-Warning "Device not found in Active Directory"  
        }
    } catch {
        Write-host " Fail" -ForegroundColor Red
        Write-Error "$($_.Exception.Message)"
    }
} #endregion AD

Set-Location $env:SystemDrive
if ($PSBoundParameters.ContainsKey("AAD") -or 
    $PSBoundParameters.ContainsKey("Intune") -or 
    $PSBoundParameters.ContainsKey("Autopilot") -or 
    $PSBoundParameters.ContainsKey("All")) {
        $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
}