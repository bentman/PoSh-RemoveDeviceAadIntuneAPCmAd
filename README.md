# Remove-DeviceApIntuneAadCmAd.ps1

## Description:  
This PowerShell script is a one-stop solution for administrators seeking to efficiently delete device records from Azure AD (AAD), Intune, Autopilot, ConfigMgr, & Active Directory (AD). It is particularly beneficial for tidying up post Autopilot test deployments. 

***
## Prerequisites:

- For all scenarios, the user account must have the required permissions to read and delete device records.
- Necessary Microsoft Graph modules will be installed for the user if they aren't present.
- **Autopilot (-Autopilot), Intune (-Intune), and Azure Active Directory (-AAD)**:
  - The Microsoft Graph PowerShell enterprise application 
      - ~~Intune App ID d1ddf0e4-d672-4dae-b554-9d5bdfd93547 is required.~~
      - *Intune App-ID for access to Graph-API has been deprecated 2024-04-01*
        - [More info in ReadMe.md @ powershell-intune-samples](https://github.com/microsoftgraph/powershell-intune-samples/tree/9d0dac47b1058584e1026119d4fd7f635eb446d5)
        - [Better info @ oofhours.com ;-)](https://oofhours.com/2024/03/29/using-a-well-known-intune-app-id-for-access-to-graph-not-for-much-longer/)
      - Create unique App-Id for each use...
        - [Quickstart: Register an application with the Microsoft identity platform](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
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

![Remove-DeviceCmAdCsv](/assets/Remove-DeviceCmAdCsv.png "Remove-DeviceCmAdCsv")

### Contributions

Contributions are welcome! Please open an issue or submit a pull request if you have suggestions or enhancements.

### License

This script is distributed without any warranty; use at your own risk.
This project is licensed under the GNU General Public License v3. 
See [GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.html) for details.
