# Get-DefenderPricingPlan

## Description
`Get-DefenderPricingPlan.ps1` is a specialized PowerShell script designed to audit **Microsoft Defender for Servers** pricing tiers at the individual Virtual Machine level. 

Unlike standard scripts that only check subscription-level settings, this tool queries the Azure Resource Manager (ARM) API to determine the effective plan (**P1**, **P2**, or **Free**) for every VM across your specified subscriptions. It provides a color-coded console summary and detailed CSV reporting for audit compliance and cost management.



## Features
* **Per-VM Granularity**: Identifies specific VMs that might be overriding subscription-level pricing.
* **Intelligent Authentication**: Automatically handles Azure context and token conversion (including SecureString handling).
* **Progress Tracking**: Real-time progress bars for long-running scans across large environments.
* **Global Limit Control**: Prevents excessive API calls by capping the total number of VMs scanned across all subscriptions.
* **Multi-Subscription Reporting**: Provides both an overall summary and a per-subscription breakdown.

## Prerequisites
* **PowerShell**: Version 7.x (recommended) or 5.1.
* **Az Module**: Requires `Az.Accounts` and `Az.Compute`.
* **Connectivity**: Access to `management.azure.com`.
* **Permissions**: **Reader** access (or higher) on all target subscriptions.

## Installation
```powershell
# Clone the repository
git clone https://github.com/yvperren/Get-DefenderPricingPlan.git

# Navigate to the directory
cd Get-DefenderPricingPlan
```

## Usage

### 1. Interactive Mode
Run the script without parameters to be prompted for subscription IDs. You can paste a comma-separated list directly into the prompt.
```powershell
Connect-AzAccount
.\Get-DefenderPricingPlan.ps1
```

### 2. Targeting Specific Subscriptions
Pass one or more specific Subscription IDs to bypass the interactive prompt.
```powershell
.\Get-DefenderPricingPlan.ps1 -SubscriptionId "00000000-1111-2222-3333-444444444444", "abc123de-45fg-67hi-89jk-lmnopqrs"
```

### 3. Limited Scan (Global Limit)
Use the `-Limit` parameter to stop the script after a certain number of VMs have been processed globally across all provided subscriptions.
```powershell
.\Get-DefenderPricingPlan.ps1 -SubscriptionId "your-sub-id" -Limit 10
```

### 4. Audit with CSV Export
Run a scan and save the results to a specific file path.
```powershell
.\Get-DefenderPricingPlan.ps1 -SubscriptionId "your-sub-id" -ExportCsv -CsvPath "C:\Audits\DefenderReport.csv"
```

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `-SubscriptionId` | `String[]` | No | An array of Azure Subscription IDs to scan. |
| `-Limit` | `Int` | No | Maximum number of VMs to check across all subscriptions. |
| `-ExportCsv` | `Switch` | No | If present, exports the results to a CSV file. |
| `-CsvPath` | `String` | No | Custom path for the CSV. Defaults to `.\vm-defender-servers-plan-report.csv`. |

## Technical Output Logic
The script visualizes the protection state using the following logic:
* **Green (P2)**: Defender for Servers Plan 2 is active.
* **Yellow (P1)**: Defender for Servers Plan 1 is active.
* **Red (Free)**: No Defender for Servers protection active.
* **Gray (Unknown)**: Indicates an unexpected state or error.

---

**Author**: [yvperren](https://github.com/yvperren)  
**License**: MIT License
