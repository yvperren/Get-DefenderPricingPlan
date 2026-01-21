
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1000000)]
    [int]$Limit,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCsv,

    [Parameter(Mandatory = $false)]
    [string]$CsvPath = ".\vm-defender-servers-plan-report.csv"
)

$ErrorActionPreference = 'Stop'

# ---------------------------
# Helpers
# ---------------------------
function Ensure-AzLogin {
    try {
        $ctx = Get-AzContext
        if ($null -ne $ctx -and $null -ne $ctx.Account) { return $true }
        Write-Host "No Azure context found. Please run Connect-AzAccount and retry." -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Host ("Failed to read Azure context: {0}" -f $_.Exception.Message) -ForegroundColor Red
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
    $tokenObj = $null
    try {
        $tokenObj = Get-AzAccessToken -ResourceTypeName Arm
    }
    catch {
        # fallback
        $tokenObj = Get-AzAccessToken
    }

    $tokenPlain = $null
    if ($tokenObj.Token -is [System.Security.SecureString]) {
        $tokenPlain = Convert-SecureStringToPlainText -SecureString $tokenObj.Token
    }
    else {
        $tokenPlain = [string]$tokenObj.Token
    }

    if ([string]::IsNullOrWhiteSpace($tokenPlain)) {
        throw "Access token conversion failed (token is empty). Re-run Connect-AzAccount and retry."
    }

    return @{
        Authorization  = "Bearer $tokenPlain"
        "Content-Type" = "application/json"
    }
}

function Get-PlanColor {
    param([string]$Plan)

    switch ((($Plan ?? '').Trim()).ToUpperInvariant()) {
        'P2'   { return 'Green' }
        'P1'   { return 'DarkYellow' }
        'FREE' { return 'Red' }
        default { return 'Gray' }
    }
}

function Normalize-Plan {
    param(
        [string]$SubPlan,
        [string]$PricingTier
    )

    if (-not [string]::IsNullOrWhiteSpace($SubPlan)) {
        return $SubPlan.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($PricingTier)) {
        if ($PricingTier.Trim().Equals("Free", "InvariantCultureIgnoreCase")) { return "Free" }
        if ($PricingTier.Trim().Equals("Standard", "InvariantCultureIgnoreCase")) { return "Standard" }
        return $PricingTier.Trim()
    }

    return "Unknown"
}

# ---------------------------
# Input handling
# ---------------------------
if (-not $SubscriptionId -or $SubscriptionId.Count -eq 0 -or [string]::IsNullOrWhiteSpace($SubscriptionId[0])) {
    $raw = Read-Host "Enter Azure subscription ID(s) (comma-separated allowed)"
    $SubscriptionId = $raw -split '[,; ]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

if (-not (Ensure-AzLogin)) { return }

try { Disable-AzContextAutosave -Scope Process | Out-Null } catch { }

$headers = Get-ArmAuthHeaders

# ---------------------------
# Main
# ---------------------------
$apiVersion = "2024-01-01"
$pricingName = "VirtualMachines"  # must match supported plan name (case-sensitive)

$allResults = New-Object System.Collections.Generic.List[object]

# ✅ NEW: global remaining counter (Limit across all subscriptions)
$Remaining = if ($Limit -and $Limit -gt 0) { $Limit } else { [int]::MaxValue }

# ✅ NEW: labeled outer loop so we can break out of BOTH loops when Remaining hits 0
:AllSubs foreach ($sub in $SubscriptionId) {

    if ($Remaining -le 0) { break AllSubs }  # just in case

    Write-Host ""
    Write-Host ("=== Subscription: {0} ===" -f $sub) -ForegroundColor Cyan

    try {
        Set-AzContext -SubscriptionId $sub | Out-Null
    }
    catch {
        Write-Host ("Failed to set Az context to subscription '{0}': {1}" -f $sub, $_.Exception.Message) -ForegroundColor Red
        continue
    }

    # Subscription-level pricing (useful context)
    $subPricingUrl = "https://management.azure.com/subscriptions/$sub/providers/Microsoft.Security/pricings/$pricingName`?api-version=$apiVersion"
    $subPlan = $null
    try {
        $subPricing = Invoke-RestMethod -Method Get -Uri $subPricingUrl -Headers $headers
        $subPlan = Normalize-Plan -SubPlan $subPricing.properties.subPlan -PricingTier $subPricing.properties.pricingTier
        Write-Host ("Subscription-level plan for {0}: {1}" -f $pricingName, $subPlan) -ForegroundColor Cyan
    }
    catch {
        Write-Host ("Warning: couldn't read subscription-level pricing: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }

    $vms = Get-AzVM
    if (-not $vms -or $vms.Count -eq 0) {
        Write-Host ("No VMs found in subscription {0}" -f $sub) -ForegroundColor Yellow
        continue
    }

    # ✅ CHANGED: apply global limit by selecting first $Remaining VMs in THIS subscription
    $vmsToCheck = $vms | Select-Object -First $Remaining   # Select-Object -First supports limiting output [1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/select-object?view=powershell-7.5)
    $total = @($vmsToCheck).Count

    if ($Limit -and $Limit -gt 0) {
        Write-Host ("Checking {0} VMs out of {1} in subscription {2} (global remaining before this sub: {3})..." -f $total, $vms.Count, $sub, $Remaining) -ForegroundColor Cyan
    }
    else {
        Write-Host ("Checking {0} VMs in subscription {1}..." -f $total, $sub) -ForegroundColor Cyan
    }

    $i = 0

    foreach ($vm in $vmsToCheck) {
        $i++
        $percent = [math]::Round(($i / [math]::Max($total, 1)) * 100, 2)

        Write-Progress -Activity "Processing VMs ($sub)" -Status ("{0}/{1}" -f $i, $total) -PercentComplete $percent

        $vmName = $vm.Name
        $vmId = $vm.Id

        try {
            $vmPricingUrl = "https://management.azure.com$vmId/providers/Microsoft.Security/pricings/$pricingName`?api-version=$apiVersion"
            $vmPricing = Invoke-RestMethod -Method Get -Uri $vmPricingUrl -Headers $headers

            $plan = Normalize-Plan -SubPlan $vmPricing.properties.subPlan -PricingTier $vmPricing.properties.pricingTier
            $color = Get-PlanColor -Plan $plan

            Write-Host ("{0,-35} -> {1}" -f $vmName, $plan) -ForegroundColor $color

            $allResults.Add([pscustomobject]@{
                SubscriptionId = $sub
                VmName         = $vmName
                VmId           = $vmId
                SubPlan        = $plan
                Scope          = "VM"
                Error          = $null
            }) | Out-Null
        }
        catch {
            Write-Host ("{0,-35} -> ERROR: {1}" -f $vmName, $_.Exception.Message) -ForegroundColor Red

            $allResults.Add([pscustomobject]@{
                SubscriptionId = $sub
                VmName         = $vmName
                VmId           = $vmId
                SubPlan        = "Error"
                Scope          = "VM"
                Error          = $_.Exception.Message
            }) | Out-Null
        }

        # ✅ NEW: decrement global remaining, and stop EVERYTHING when it reaches 0
        if ($Limit -and $Limit -gt 0) {
            $Remaining--
            if ($Remaining -le 0) {
                Write-Progress -Activity "Processing VMs ($sub)" -Completed
                break AllSubs   # labeled break exits outer subscription loop [2](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_break?view=powershell-7.5)
            }
        }
    }

    Write-Progress -Activity "Processing VMs ($sub)" -Completed
}

# ---------------------------
# Output
# ---------------------------
Write-Host ""
Write-Host "Results:" -ForegroundColor Cyan
$allResults | Sort-Object SubscriptionId, VmName | Format-Table -AutoSize SubscriptionId, VmName, SubPlan, Scope, Error

Write-Host ""
Write-Host "Summary (overall):" -ForegroundColor Cyan
$groups = $allResults | Group-Object SubPlan
function Get-Count([string]$name) {
    $g = $groups | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if ($null -ne $g) { return [int]$g.Count }
    return 0
}
$p2 = Get-Count 'P2'
$p1 = Get-Count 'P1'
$free = Get-Count 'Free'
$other = $allResults.Count - ($p2 + $p1 + $free)

Write-Host ("P2   : {0}" -f $p2) -ForegroundColor Green
Write-Host ("P1   : {0}" -f $p1) -ForegroundColor DarkYellow
Write-Host ("Free : {0}" -f $free) -ForegroundColor Red
if ($other -gt 0) {
    Write-Host ("Other/Error/Standard/Unknown : {0}" -f $other) -ForegroundColor Gray
}

Write-Host ""
Write-Host "Summary (per subscription):" -ForegroundColor Cyan
$allResults | Group-Object SubscriptionId | ForEach-Object {
    $sub = $_.Name
    $items = $_.Group
    $p2s = ($items | Where-Object SubPlan -eq 'P2').Count
    $p1s = ($items | Where-Object SubPlan -eq 'P1').Count
    $frees = ($items | Where-Object SubPlan -eq 'Free').Count
    $others = $items.Count - ($p2s + $p1s + $frees)

    Write-Host ("{0}: P2={1}, P1={2}, Free={3}, Other={4}" -f $sub, $p2s, $p1s, $frees, $others) -ForegroundColor Cyan
}

if ($ExportCsv) {
    try {
        $allResults | Sort-Object SubscriptionId, VmName | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host ("CSV saved to: {0}" -f $CsvPath) -ForegroundColor Green
    }
    catch {
        Write-Host ("Failed to export CSV: {0}" -f $_.Exception.Message) -ForegroundColor Red
        throw
    }
}
