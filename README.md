## Get-DefenderPricingPlan

## Description

Get-DefenderPricingPlan.ps1 is a PowerShell script designed to retrieve and display Microsoft Defender for Cloud pricing tiers across Azure subscriptions. It provides a consolidated view of which Defender plans (such as Servers, Storage, Key Vault, and Databases) are currently active and whether they are on the 'Free' or 'Standard' (paid) tier.

## Features

Multi-Subscription Support: Iterates through all subscriptions accessible in the current Azure context.

Comprehensive Coverage: Identifies the pricing configuration for all available Defender for Cloud resource types.

Audit-Ready: Provides a structured output suitable for auditing and cost management.

## Prerequisites

PowerShell 7.x (recommended) or PowerShell 5.1.

Az PowerShell Module: Specifically Az.Accounts and Az.Security.

Permissions: An active Azure session with at least Reader permissions on the target subscriptions.

## Installation

Clone the repository to your local machine: 

```powershell git clone [https://github.com/yvperren/Get-DefenderPricingPlan.git](https://github.com/yvperren/Get-DefenderPricingPlan.git) cd Get-DefenderPricingPlan ```

## Usage

### Basic Execution

Audit all subscriptions accessible in the current context and output the results directly to the console: 

```powershell Connect-AzAccount .\Get-DefenderPricingPlan.ps1 ```

### Execution for a Specific Subscription

If you want to target a single specific subscription by its ID: 

```powershell .\Get-DefenderPricingPlan.ps1 -SubscriptionId ***00000000**-**0000**-**0000**-**0000**-**000000000000*** ```

### Execution for Multiple Specific Subscriptions

You can pass an array of subscription IDs to the script to audit a specific subset of your environment: 

```powershell $mySubs = @(***00000000**-**1111**-**2222**-**3333**-**444444444444***, ***55555555**-**6666**-**7777**-**8888**-**999999999999***) foreach ($sub in $mySubs) { .\Get-DefenderPricingPlan.ps1 -SubscriptionId $sub } ```

### Exporting Results to CSV

To save the output for reporting or analysis, you can export the results to a **CSV** file: 

```powershell .\Get-DefenderPricingPlan.ps1 | Export-Csv -Path *DefenderPricingReport.csv* -NoTypeInformation ```

## Output Details

The script returns an object for each resource type with the following properties:

SubscriptionName: The name of the Azure subscription.

PlanName: The name of the Defender plan (e.g., VirtualMachines, KeyVaults).

PricingTier: The tier assigned (Free or Standard).

SubPlan: Displays specific sub-plan details (e.g., P1 or P2) where applicable.

License: This project is licensed under the **MIT** License.
