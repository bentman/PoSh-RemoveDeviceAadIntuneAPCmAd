<#
.SYNOPSIS
    Function: Remove-DeviceCmAdCsv - locates and removes devices from both ConfigMgr and Active Directory using serial numbers provided in a CSV file.
.DESCRIPTION
    Accepts a path to a CSV file with serial numbers listed in the first column. 
    Attempts to find the device associated with each serial number in ConfigMgr and fetches its computer name
    Searches for and removes the device from both ConfigMgr and Active Directory.
.PARAMETER CsvFilePath
    The full path to the CSV file which contains serial numbers in the first column.
.EXAMPLE
    Remove-DeviceCmAdCsv -CsvFilePath "path_to_your_csv_file.csv"
#>

function Remove-DeviceCmAdCsv {
    param ([Parameter(Mandatory=$true)][string]$CsvFilePath)
    # Import the CSV file
    $serialNumbers = Import-Csv -Path $CsvFilePath
    # Connect to ConfigMgr Site
    $SiteCode = (Get-PSDrive -PSProvider CMSITE -ErrorAction Stop).Name
    Push-Location "$($SiteCode):" -ErrorAction Stop
    foreach ($row in $serialNumbers) {
        $serialNumber = $row.'Serial Number'
        $computerName = $null
        # Attempt to locate the device in ConfigMgr using serial number
        Write-Host "Processing Serial Number: $serialNumber"
        Write-Host "Locating device in ConfigMgr" -NoNewline
        Write-Host "..." -NoNewline -ForegroundColor Magenta
        # ConfigMgr logic
        try {
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
                    Write-Host " Success" -ForegroundColor Green
                } catch {
                    Write-Host " Fail" -ForegroundColor Red
                    Write-Error "$($_.Exception.Message)"
                }
            } elseif ($ConfigMgrDevices.Count -gt 1) {
                Write-Host " Fail" -ForegroundColor Red
                Write-Warning "Multiple devices found in ConfigMgr with the same serial number. Serial number must be unique." 
                Continue
            } else {
                Write-Host " Fail" -ForegroundColor Red
                Write-Warning "Device not found in ConfigMgr using the provided serial number."    
            }
        }
        # Pop out of the ConfigMgr drive, since we don't need it for AD operations
        Pop-Location
        # AD operations start here
        if ($computerName) {
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
                    $DirectoryEntry = $ComputerAccount.GetDirectoryEntry()
                    $DirectoryEntry.DeleteTree()
                    Write-Host " Success" -ForegroundColor Green
                } else {
                    Write-host " Fail" -ForegroundColor Red
                    Write-Warning "Device not found in Active Directory"  
                }
            } catch {
                Write-host " Fail" -ForegroundColor Red
                Write-Error "$($_.Exception.Message)"
            }
        }
        # Push back into the ConfigMgr drive for the next iteration
        Push-Location "$($SiteCode):" -ErrorAction Stop
    }
    # Pop out of the ConfigMgr drive one final time at the end
    Pop-Location
}

# Uncomment the line below to test the function directly after opening the script 
# Remove-DeviceCmAdCsv -CsvFilePath "path_to_your_csv_file.csv"
