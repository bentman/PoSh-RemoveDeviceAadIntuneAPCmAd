# Remove-DeviceApIntuneAadCmAd.ps1

## Description:  
This PowerShell script is a one-stop solution for administrators seeking to efficiently delete device records from Azure AD (AAD), Intune, Autopilot, ConfigMgr, & Active Directory (AD). It is particularly beneficial for tidying up post Autopilot test deployments. 

***
## Prerequisites:

- For all scenarios, the user account must have the required permissions to read and delete device records.
- Necessary Microsoft Graph modules will be installed for the user if they aren't present.
- **Autopilot (-Autopilot), Intune (-Intune), and Azure Active Directory (-AAD)**:
  - The Microsoft Graph PowerShell enterprise application 
      - App ID 14d82eec-204b-4c2f-b7e8-296a70dab67e is required.
  - The following permissions, granted with admin consent, are essential:
      - DeviceManagementServiceConfig.ReadWrite.All (for Autopilot)
      - DeviceManagementManagedDevices.ReadWrite.All (for Intune)
      - Directory.AccessAsUser.All (for Azure AD)
- **Configuration Manager (-ConfigMgr)**:
  - ConfigMgr PowerShell module should be installed on the host workstation.
- **Active Directory (-AD)**:
  - The host workstation needs to be joined to the domain.
  - The host workstation should be able to communicate with a domain controller.

***Note:*** Always ensure you have backups and have tested in a non-production environment before running any script on live systems.

***
## Usage:

**Cloud Only** | Remove device by serial number from Autopilot, Azure AD, and Intune.
```powershell
.\Remove-DeviceApIntuneAadCmAd.ps1 -serialNumber "YourDeviceSerialNumber" -Autopilot -Intune -AAD 
```
**Hybrid** | Remove device by serial number from Autopilot, Intune, Azure AD, ConfigMgr, and Active Directory.
```powershell
.\Remove-DeviceApIntuneAadCmAd.ps1 -serialNumber "YourDeviceSerialNumber" -All
```
**On-Prem** | Remove device by serial number from ConfigMgr and Active Directory.
```powershell
.\Remove-DeviceApIntuneAadCmAd.ps1 -serialNumber "YourDeviceSerialNumber" -ConfigMgr -AD
```
**AD Only** | Active Directory does not store $serialNumber, so if you are only removing from AD use this one.
```powershell
.\Remove-DeviceApIntuneAadCmAd.ps1 -computerName "YourDevice-ComputerName" -AD
```

###
## Contributions

Contributions are welcome. Please open an issue or submit a pull request.

### GNU General Public License
This script is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This script is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this script. If not, see https://www.gnu.org/licenses/. 