# Get-DefenderPricingPlan

## Description
`Get-DefenderPricingPlan.ps1` is a specialized PowerShell script designed to audit **Microsoft Defender for Servers** pricing tiers at a granular level. 

Unlike standard scripts that only check subscription-level settings, this tool queries the Azure Resource Manager (ARM) API to determine the effective plan (**P1**, **P2**, or **Free**) for every supported resource across your specified subscriptions. It supports **Azure Virtual Machines**, **Virtual Machine Scale Sets (VMSS)**, and **Azure Arc-enabled servers**.

## Features
* **Multi-Resource Granularity**: Identifies pricing for VMs, Scale Sets, and Arc machines that may override subscription-level defaults.
* **Unified Resource Discovery**: Automatically scans for `Microsoft.Compute/virtualMachines`, `virtualMachineScaleSets`, and `Microsoft.HybridCompute/machines`.
* **Intelligent Authentication**: Handles Azure context management and token conversion (including SecureString processing).
* **Progress Tracking**: Real-time progress bars for visibility during large-scale environment scans.
* **Global Limit Control**: Prevents excessive API calls by capping the total number of resources scanned across all subscriptions.
* **Consolidated Reporting**: Provides a per-scope summary (VM vs. VMSS vs. Arc) and optional CSV export.

## Prerequisites
* **PowerShell**: Version 7.x (recommended) or 5.1.
* **Az Module**: Requires `Az.Accounts`, `Az.Compute`, and `Az.Resources`.
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
Run the script without parameters to be prompted for subscription IDs. You can paste a comma-separated list of IDs directly.
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
Use the `-Limit` parameter to stop the script after a certain number of resources have been processed globally.
```powershell
.\Get-DefenderPricingPlan.ps1 -Limit 50
```

### 4. Audit with CSV Export
Run a scan and save the results to a specific file path.
```powershell
.\Get-DefenderPricingPlan.ps1 -ExportCsv -CsvPath "C:\Audits\DefenderReport.csv"
```

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `-SubscriptionId` | `String[]` | No | An array of Azure Subscription IDs to scan. |
| `-Limit` | `Int` | No | Maximum number of resources to check across all subscriptions. |
| `-ExportCsv` | `Switch` | No | If present, exports the results to a CSV file. |
| `-CsvPath` | `String` | No | Custom path for the CSV. Defaults to `.\server-defender-plan-report.csv`. |

## Technical Output Logic
The script visualizes the protection state using the following logic:
* **Green (P2 / Standard)**: Defender for Servers Plan 2 or the legacy "Standard" tier is active.
* **DarkYellow (P1)**: Defender for Servers Plan 1 is active.
* **Red (Free)**: No Defender for Servers protection is active.
* **Gray (Unknown)**: Indicates an unexpected state or error.

The **Scope** column identifies the resource type:
* `VM`: Azure Virtual Machine
* `VMSS`: Virtual Machine Scale Set
* `Arc`: Azure Arc-enabled Server

---

**Author**: [yvperren](https://github.com/yvperren)  
**License**: MIT License
