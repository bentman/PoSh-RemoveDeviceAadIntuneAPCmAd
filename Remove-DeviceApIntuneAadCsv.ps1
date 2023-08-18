<#
.SYNOPSIS
    Function: Remove-DeviceApIntuneAadCsv - locates and removes devices from Autopilot, Intune, and Azure AD using serial numbers provided in a CSV file.
.DESCRIPTION
    Accepts a path to a CSV file with serial numbers listed in the first column. 
    Attempts to find the device associated with each serial number in Autopilot, Intune, and Azure AD, then removes it.
.PARAMETER CsvFilePath
    The full path to the CSV file which contains serial numbers in the first column.
.EXAMPLE
    Remove-DeviceApIntuneAadCsv -CsvFilePath "path_to_your_csv_file.csv"
#>

function Remove-DeviceApIntuneAadCsv {
    param ([Parameter(Mandatory=$true)][string]$CsvFilePath)
    # MS-Graph Modules list
    $moduleNames = @( 
        "Microsoft.Graph.Identity.DirectoryManagement",
        "Microsoft.Graph.DeviceManagement",
        "Microsoft.Graph.DeviceManagement.Enrollment"
    )
    # Authenticate to Microsoft Graph
    function Connect-MsftGraph {
        $token = Get-MgAccessToken
        # Import necessary Microsoft.Graph modules
        foreach ($module in $moduleNames) {
            Import-Module $module -Force
        }
        return $token
    }
    # Import the CSV file
    $serialNumbers = Import-Csv -Path $CsvFilePath
    # Authenticate to services and setup necessary modules
    $token = Connect-MsftGraph
    foreach ($row in $serialNumbers) {
        $serialNumber = $row[0]
        # Attempt to locate and remove the device in Autopilot
        Write-Host "Processing Serial Number: $serialNumber"
        Write-Host "Locating device in Autopilot" -NoNewline
        Write-Host "..." -NoNewline -ForegroundColor Magenta
        try {
            $autopilotDevice = Get-MgDeviceManagementImportedWindowsAutopilotDeviceIdentity -Filter "serialNumber eq '$serialNumber'"
            if ($autopilotDevice) {
                Remove-MgDeviceManagementImportedWindowsAutopilotDeviceIdentity -DeviceId $autopilotDevice.id
                Write-Host " Success" -ForegroundColor Green
            } else {
                Write-Host " Fail" -ForegroundColor Red
                Write-Warning "Device not found in Autopilot."
            }
        } catch {
            Write-Host " Fail" -ForegroundColor Red
            Write-Error "$($_.Exception.Message)"
        }
        # Attempt to locate and remove the device in Intune
        Write-Host "Locating device in Intune" -NoNewline
        Write-Host "..." -NoNewline -ForegroundColor Cyan
        try {
            $intuneDevice = Get-MgDeviceManagementDevice -Filter "serialNumber eq '$serialNumber'"
            if ($intuneDevice) {
                Remove-MgDeviceManagementDevice -DeviceId $intuneDevice.id
                Write-Host " Success" -ForegroundColor Green
            } else {
                Write-Host " Fail" -ForegroundColor Red
                Write-Warning "Device not found in Intune."
            }
        } catch {
            Write-Host " Fail" -ForegroundColor Red
            Write-Error "$($_.Exception.Message)"
        }
        # Attempt to locate and remove the device in Azure AD
        Write-Host "Locating device in Azure AD" -NoNewline
        Write-Host "..." -NoNewline -ForegroundColor Blue
        try {
            $azureDevice = Get-MgDirectoryDevice -Filter "devicePhysicalIds/any(id:id eq '$serialNumber')"
            if ($azureDevice) {
                Remove-MgDirectoryDevice -DeviceId $azureDevice.id
                Write-Host " Success" -ForegroundColor Green
            } else {
                Write-Host " Fail" -ForegroundColor Red
                Write-Warning "Device not found in Azure AD."
            }
        } catch {
            Write-Host " Fail" -ForegroundColor Red
            Write-Error "$($_.Exception.Message)"
        }
    }
}

# Uncomment the line below to test the function directly after opening the script 
# Remove-DeviceApIntuneAadCsv -CsvFilePath "path_to_your_csv_file.csv"
