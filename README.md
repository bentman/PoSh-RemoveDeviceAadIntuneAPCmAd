# Remove-DeviceCmAdAadIntuneAp.ps1

## Description:  
This PowerShell script is a one-stop solution for administrators seeking to efficiently delete device records from ConfigMgr, Active Directory (AD), Azure AD (AAD), Intune, and Autopilot. It is particularly beneficial for tidying up post Autopilot test deployments. Specifically designed for "hybrid" environments, this script uses device serial number and uses "on-prem" Configuration Manager

***
## Prerequisites:

- For all scenarios, the user account must have the required permissions to read and delete device records.
- Necessary Microsoft Graph modules will be installed for the user if they aren't present.
- **Configuration Manager (-ConfigMgr)**:
  - ConfigMgr PowerShell module should be installed on the host workstation.
- **Active Directory (-AD)**:
  - The host workstation needs to be joined to the domain.
  - The host workstation should be able to communicate with a domain controller.
- **Azure Active Directory (-AAD), -Intune, and -Autopilot**:
  - The Microsoft Graph PowerShell enterprise application with App ID 14d82eec-204b-4c2f-b7e8-296a70dab67e is required.
  - The following permissions, granted with admin consent, are essential:
      - Directory.AccessAsUser.All (for Azure AD)
      - DeviceManagementManagedDevices.ReadWrite.All (for Intune)
      - DeviceManagementServiceConfig.ReadWrite.All (for Autopilot)

***Note:*** Always ensure you have backups and have tested in a non-production environment before running any script on live systems.

***
## Usage:

Cloud Only | This will remove the device with the specified serial number from both Azure AD, Intune and Autopilot.
```powershell
.\Remove-DeviceCmAdAadIntuneAp.ps1 -serialNumber "YourDeviceSerialNumber" -AAD - Intune -Autopilot
```
Hybrid | This will remove the device with the specified serial number from Azure AD, Intune, Autopilot, ConfigMgr, and Active Directory.
```powershell
.\Remove-DeviceCmAdAadIntuneAp.ps1 -serialNumber "YourDeviceSerialNumber" -All
```
On-Prem | This will remove the device with the specified serial number from both ConfigMgr and Active Directory.
```powershell
.\Remove-DeviceCmAdAadIntuneAp.ps1 -serialNumber "YourDeviceSerialNumber" -ConfigMgr -AD
```
AD Only | Active Directory does not natively store $serialNumber, so if you are only removing from AD use this one.
```powershell
.\Remove-DeviceCmAdAadIntuneAp.ps1 -computerName "YourDevice-ComputerName" -AD
```

###
## Contributions

Contributions are welcome. Please open an issue or submit a pull request.

### GNU General Public License
This script is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This script is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this script. If not, see https://www.gnu.org/licenses/.