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
    [string]$CsvPath = ".\server-defender-plan-report.csv"
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
        'P2'    { return 'Green' }
        'P1'    { return 'DarkYellow' }
        'FREE'  { return 'Red' }
        'STANDARD' { return 'Green' }
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

function Get-ScopeType {
    param([string]$ResourceType)
    switch -Wildcard ($ResourceType) {
        "*Microsoft.Compute/virtualMachines" { return "VM" }
        "*Microsoft.Compute/virtualMachineScaleSets" { return "VMSS" }
        "*Microsoft.HybridCompute/machines" { return "Arc" }
        default { return "Unknown" }
    }
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
$pricingName = "VirtualMachines"

$allResults = New-Object System.Collections.Generic.List[object]
$Remaining = if ($Limit -and $Limit -gt 0) { $Limit } else { [int]::MaxValue }

:AllSubs foreach ($sub in $SubscriptionId) {

    if ($Remaining -le 0) { break AllSubs }

    Write-Host ""
    Write-Host ("=== Subscription: {0} ===" -f $sub) -ForegroundColor Cyan

    try {
        Set-AzContext -SubscriptionId $sub | Out-Null
    }
    catch {
        Write-Host ("Failed to set Az context to subscription '{0}': {1}" -f $sub, $_.Exception.Message) -ForegroundColor Red
        continue
    }

    # Subscription-level pricing
    $subPricingUrl = "https://management.azure.com/subscriptions/$sub/providers/Microsoft.Security/pricings/$pricingName`?api-version=$apiVersion"
    try {
        $subPricing = Invoke-RestMethod -Method Get -Uri $subPricingUrl -Headers $headers
        $subPlan = Normalize-Plan -SubPlan $subPricing.properties.subPlan -PricingTier $subPricing.properties.pricingTier
        Write-Host ("Subscription-level plan for {0}: {1}" -f $pricingName, $subPlan) -ForegroundColor Cyan
    }
    catch {
        Write-Host ("Warning: couldn't read subscription-level pricing: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }

    # Unified resource discovery for VM, VMSS, and Arc
    $resources = Get-AzResource | Where-Object { 
        $_.ResourceType -eq "Microsoft.Compute/virtualMachines" -or 
        $_.ResourceType -eq "Microsoft.Compute/virtualMachineScaleSets" -or 
        $_.ResourceType -eq "Microsoft.HybridCompute/machines"
    }

    if (-not $resources -or $resources.Count -eq 0) {
        Write-Host ("No VMs, VMSS, or Arc machines found in subscription {0}" -f $sub) -ForegroundColor Yellow
        continue
    }

    $resourcesToCheck = $resources | Select-Object -First $Remaining
    $total = @($resourcesToCheck).Count

    Write-Host ("Checking {0} resources in subscription {1}..." -f $total, $sub) -ForegroundColor Cyan

    $i = 0
    foreach ($res in $resourcesToCheck) {
        $i++
        $percent = [math]::Round(($i / [math]::Max($total, 1)) * 100, 2)
        $scope = Get-ScopeType -ResourceType $res.ResourceType

        Write-Progress -Activity "Processing resources ($sub)" -Status ("{0}/{1} ({2})" -f $i, $total, $res.Name) -PercentComplete $percent

        try {
            # Use the resource ID to call the pricing API
            $pricingUrl = "https://management.azure.com$($res.ResourceId)/providers/Microsoft.Security/pricings/$pricingName`?api-version=$apiVersion"
            $pricing = Invoke-RestMethod -Method Get -Uri $pricingUrl -Headers $headers

            $plan = Normalize-Plan -SubPlan $pricing.properties.subPlan -PricingTier $pricing.properties.pricingTier
            $color = Get-PlanColor -Plan $plan

            Write-Host ("[{0,-4}] {1,-35} -> {2}" -f $scope, $res.Name, $plan) -ForegroundColor $color

            $allResults.Add([pscustomobject]@{
                SubscriptionId = $sub
                ResourceName   = $res.Name
                ResourceId     = $res.ResourceId
                SubPlan        = $plan
                Scope          = $scope
                Error          = $null
            }) | Out-Null
        }
        catch {
            Write-Host ("[{0,-4}] {1,-35} -> ERROR: {2}" -f $scope, $res.Name, $_.Exception.Message) -ForegroundColor Red
            $allResults.Add([pscustomobject]@{
                SubscriptionId = $sub
                ResourceName   = $res.Name
                ResourceId     = $res.ResourceId
                SubPlan        = "Error"
                Scope          = $scope
                Error          = $_.Exception.Message
            }) | Out-Null
        }

        if ($Limit -and $Limit -gt 0) {
            $Remaining--
            if ($Remaining -le 0) { break AllSubs }
        }
    }
}

# ---------------------------
# Output / Summary
# ---------------------------
Write-Host ""
Write-Host "Results:" -ForegroundColor Cyan
$allResults | Sort-Object SubscriptionId, ResourceName | Format-Table -AutoSize SubscriptionId, ResourceName, SubPlan, Scope, Error

Write-Host ""
Write-Host "Summary (per Scope):" -ForegroundColor Cyan
$allResults | Group-Object Scope | ForEach-Object {
    $s = $_.Name
    $p2 = ($_.Group | Where-Object SubPlan -eq 'P2').Count
    $p1 = ($_.Group | Where-Object SubPlan -eq 'P1').Count
    $free = ($_.Group | Where-Object SubPlan -eq 'Free').Count
    Write-Host ("{0,-5}: P2={1}, P1={2}, Free={3}, Total={4}" -f $s, $p2, $p1, $free, $_.Count)
}

if ($ExportCsv) {
    $allResults | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host ("CSV saved to: {0}" -f $CsvPath) -ForegroundColor Green
}
