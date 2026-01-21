
<#
.SYNOPSIS
Checks Microsoft Defender for Cloud pricing plans (Free, P1, P2) for Virtual Machines.

.DESCRIPTION
Queries Azure Resource Manager Microsoft.Security pricing APIs to retrieve
Defender for Cloud pricing plans at subscription and VM level.
Supports colored console output and optional CSV export.

.PARAMETER SubscriptionId
Azure subscription ID to analyze. If not provided, you are prompted.

.PARAMETER ExportCsv
Exports the result to a CSV file.

.PARAMETER CsvPath
Path to the CSV export file. Default: defender-pricing-report.csv

.EXAMPLE
.\Get-DefenderPricingPlan.ps1 -SubscriptionId <GUID>

.EXAMPLE
.\Get-DefenderPricingPlan.ps1 -SubscriptionId <GUID> -ExportCsv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCsv,

    [Parameter(Mandatory = $false)]
    [string]$CsvPath = ".\defender-pricing-report.csv"
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Ensure-AzLogin {
    try {
        $ctx = Get-AzContext
        if ($null -ne $ctx -and $null -ne $ctx.Account) { return $true }

        Write-Host "No Azure context found. Please run Connect-AzAccount and retry." -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Host "Failed to read Azure context: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Convert-SecureStringToPlainText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-ArmAuthHeaders {
    # Get-AzAccessToken output token is SecureString by default in newer Az.Accounts/Az versions. [1](https://learn.microsoft.com/en-us/powershell/module/az.accounts/get-azaccesstoken?view=azps-15.2.0)[2](https://learn.microsoft.com/en-us/powershell/azure/protect-secrets?view=azps-14.0.0)
    $tokenObj = Get-AzAccessToken -ResourceTypeName Arm

    $tokenPlain = $null
    if ($tokenObj.Token -is [System.Security.SecureString]) {
        $tokenPlain = Convert-SecureStringToPlainText -SecureString $tokenObj.Token
    }
    else {
        # older versions: token might already be a string
        $tokenPlain = [string]$tokenObj.Token
    }

    if ([string]::IsNullOrWhiteSpace($tokenPlain) -or $tokenPlain -eq 'System.Security.SecureString') {
        throw "Access token was not a valid JWT string (token conversion failed)."
    }

    return @{
        'Authorization' = "Bearer $tokenPlain"
        'Content-Type'  = 'application/json'
    }
}

function Get-PlanColor {
    param([string]$Plan)

    switch (($Plan ?? '').Trim().ToUpperInvariant()) {
        'P2'   { return 'Green' }
        'P1'   { return 'DarkYellow' }  # closest “orange” in ConsoleColor
        'FREE' { return 'Red' }
        default { return 'Gray' }
    }
}

# ------------------------------------------------------------
# 1) Setup & Context
# ------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $SubscriptionId = Read-Host "Enter Azure subscription ID"
}

if (-not (Ensure-AzLogin)) {
    return
}

try {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}
catch {
    Write-Host "Failed to set Az context to subscription '$SubscriptionId': $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# ------------------------------------------------------------
# 2) Auth headers (works in Cloud Shell + PS 5.1)
# ------------------------------------------------------------
$headers = Get-ArmAuthHeaders

# ------------------------------------------------------------
# 3) Get VMs
# ------------------------------------------------------------
$vms = Get-AzVM
if (-not $vms) {
    Write-Host "No VMs found in subscription $SubscriptionId" -ForegroundColor Yellow
    return
}

Write-Host ("Checking {0} VMs in subscription {1}..." -f $vms.Count, $SubscriptionId) -ForegroundColor Cyan

# ------------------------------------------------------------
# 4) For each VM: query Defender for Cloud pricing at RESOURCE scope
#    Using Pricings - List REST API at resource scope. [4](https://learn.microsoft.com/en-us/rest/api/defenderforcloud/pricings/list?view=rest-defenderforcloud-2024-01-01)
# ------------------------------------------------------------
$results = foreach ($vm in $vms) {
    $vmName = $vm.Name
    $plan   = 'Inherited/Unknown'

    try {
        # Resource-scope list. We'll pick the 'VirtualMachines' plan from returned list.
        $uri = "https://management.azure.com{0}/providers/Microsoft.Security/pricings?api-version=2024-01-01" -f $vm.Id
        $res = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers

        # res.value[] contains multiple plans; select VirtualMachines
        $vmPricing = $res.value | Where-Object { $_.name -eq 'VirtualMachines' } | Select-Object -First 1
        if ($null -ne $vmPricing -and $null -ne $vmPricing.properties) {
            # subPlan example: P2 in Microsoft Learn sample response. [4](https://learn.microsoft.com/en-us/rest/api/defenderforcloud/pricings/list?view=rest-defenderforcloud-2024-01-01)
            $plan = [string]$vmPricing.properties.subPlan
            if ([string]::IsNullOrWhiteSpace($plan)) {
                # fallback: pricingTier might be Free/Standard if subPlan absent
                $tier = [string]$vmPricing.properties.pricingTier
                if ($tier) { $plan = $tier } else { $plan = 'Inherited/Unknown' }
            }
        }
    }
    catch {
        # If your header accidentally contains a SecureString object, Azure returns InvalidAuthenticationToken. [3](https://github.com/Azure/azure-powershell/issues/27882)
        $plan = 'Error'
    }

    $color = Get-PlanColor -Plan $plan
    if ($plan -eq 'Error') { $color = 'Yellow' }

    Write-Host ("{0} -> {1}" -f $vmName, $plan) -ForegroundColor $color

    [pscustomobject]@{
        VmName = $vmName
        SubPlan = $plan
        VmId  = $vm.VmId
    }
}

# ------------------------------------------------------------
# 5) Output table
# ------------------------------------------------------------
Write-Host "`nResults:" -ForegroundColor Cyan
$results | Sort-Object VmName | Format-Table -AutoSize

# ------------------------------------------------------------
# 6) Summary counts (Free / P1 / P2 / Other)
# ------------------------------------------------------------
Write-Host "`nSummary:" -ForegroundColor Cyan
$groups = $results | Group-Object SubPlan

function Get-Count([string]$name) {
    $g = $groups | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if ($null -ne $g) { return [int]$g.Count }
    return 0
}

$p2   = Get-Count 'P2'
$p1   = Get-Count 'P1'
$free = Get-Count 'Free'
$other = $results.Count - ($p2 + $p1 + $free)

Write-Host ("P2   : {0}" -f $p2)   -ForegroundColor Green
Write-Host ("P1   : {0}" -f $p1)   -ForegroundColor DarkYellow
Write-Host ("Free : {0}" -f $free) -ForegroundColor Red
if ($other -gt 0) {
    Write-Host ("Other/Error/Inherited : {0}" -f $other) -ForegroundColor Gray
}

# ------------------------------------------------------------
# 7) CSV export (optional)
# ------------------------------------------------------------
if ($ExportCsv) {
    try {
        $results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host ("CSV saved to: {0}" -f $CsvPath) -ForegroundColor Green
    }
    catch {
        Write-Host ("Failed to export CSV: {0}" -f $_.Exception.Message) -ForegroundColor Red
        throw
    }
}
