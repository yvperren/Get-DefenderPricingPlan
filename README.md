
# Get-DefenderPricingPlan

A PowerShell utility to inspect **Microsoft Defender for Cloud pricing sub‑plans**  
(**Free / P1 / P2**) for **Virtual Machines** at **subscription** and **VM** scope.

The script queries Azure Resource Manager (ARM) and Microsoft Security APIs to show
which Defender for Cloud plan is enabled and where VM-level overrides exist.

---

## 🚀 Features

- ✅ Detects **Defender for Cloud pricing plan** for:
  - Subscription level
  - Individual Virtual Machines (override detection)
- 📊 Optional CSV export
- 🔄 Safe progress reporting
- ☁️ Works in: PowerShell 7+ and Azure Cloud Shell

---

## 📦 Requirements

- Azure PowerShell (`Az`) module
- An authenticated Azure session
- Minimum role:
  - **Reader** or **Security Reader** on the target subscription

---

## 🔐 Authentication

The script uses your existing Azure sign‑in:

```powershell
Connect-AzAccount
```

## 📦 Installation

git clone https://github.com/<your-username>/Get-DefenderPricingPlan.git
cd Get-DefenderPricingPlan

## ▶️ Usage

Console output only

```powershell
.\Get-DefenderPricingPlan.ps1 -SubscriptionId <SUBSCRIPTION-GUID>
```
Export results to CSV
```powershell

.\Get-DefenderPricingPlan.ps1 `
  -SubscriptionId <SUBSCRIPTION-GUID> `
  -ExportCsv

```
Custom CSV path
```powershell

.\Get-DefenderPricingPlan.ps1 `
  -SubscriptionId <SUBSCRIPTION-GUID> `
  -ExportCsv `
  -CsvPath C:\Temp\defender-pricing.csv

```

## 🖥️ Example Output

```powershell


Subscription-level plan for VirtualMachines: P2

VM-WIN-01                          P2
VM-LINUX-02                        Free
VM-APP-03                          P1


```
