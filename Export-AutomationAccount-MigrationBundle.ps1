<#
.SYNOPSIS
  Export Azure Automation migration bundle:
   - Runbooks (Published)
   - Variables (CSV)
   - ARM variable resources snippet (optional helper)

.DESCRIPTION
  Runbook export uses Export-AzAutomationRunbook with -Slot Published. [1](https://learn.microsoft.com/en-us/powershell/module/az.automation/export-azautomationrunbook?view=azps-15.4.0)
  Variables are exported as Automation assets (CSV). [2](https://learn.microsoft.com/en-us/powershell/module/az.automation/export-azautomationrunbook?view=azps-13.0.0)
  ARM variable resource type reference: Microsoft.Automation/automationAccounts/variables. [3](https://teams.microsoft.com/l/meeting/details?eventId=AAMkAGRkMTY3ZTEyLWI1ZDctNDM1NS1iMDdmLTA3MjE1OTc0N2RiMQFRAAgI3rCCk38AAEYAAAAAA7iYkyivQEWTgr0eL3bk-wcAyWlvm9M_x0KVXx0qg6_JmQAAAJIa2gAAq-01WQMQDk6qYRpdI5DVIAAH_87IfAAAEA%3d%3d)

.PARAMETER SubscriptionId
  Subscription containing the source Automation Account.

.PARAMETER ResourceGroupName
  Resource group of the source Automation Account.

.PARAMETER AutomationAccountName
  Source Automation Account name.

.PARAMETER OutputRoot
  Root output folder. Default: .\AutomationMigrationBundle

.PARAMETER IncludeDraftRunbooks
  Also attempt exporting Draft slot (optional; may fail for some runbooks depending on type/state).

.EXAMPLE
  .\Export-AutomationAccount-MigrationBundle.ps1 `
    -SubscriptionId "00000000-0000-0000-0000-000000000000" `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-legalhold" `
    -OutputRoot "C:\Temp\AutomationMigrationBundle"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string] $SubscriptionId,

  [Parameter(Mandatory=$true)]
  [string] $ResourceGroupName,

  [Parameter(Mandatory=$true)]
  [string] $AutomationAccountName,

  [Parameter()]
  [string] $OutputRoot = ".\AutomationMigrationBundle",

  [Parameter()]
  [switch] $IncludeDraftRunbooks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Folder {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Escape-JsonString {
  param([string]$s)
  if ($null -eq $s) { return "" }
  return ($s -replace '\\','\\' -replace '"','\"' -replace "`r","" -replace "`n","\n")
}

function Ensure-Module {
  param([Parameter(Mandatory=$true)][string]$Name)
  if (-not (Get-Module -ListAvailable -Name $Name)) {
    Write-Host "Installing module $Name..." -ForegroundColor Yellow
    Install-Module $Name -Scope CurrentUser -Force
  }
  Import-Module $Name -ErrorAction Stop
}

Write-Host "== Azure Automation Migration Bundle EXPORT ==" -ForegroundColor Cyan
Write-Host "SubscriptionId:       $SubscriptionId"
Write-Host "ResourceGroupName:    $ResourceGroupName"
Write-Host "AutomationAccountName:$AutomationAccountName"
Write-Host "OutputRoot:           $OutputRoot"
Write-Host ""

# Modules
Ensure-Module "Az.Accounts"
Ensure-Module "Az.Automation"

# Login/context
if (-not (Get-AzContext)) {
  Write-Host "Connecting to Azure..." -ForegroundColor Yellow
  Connect-AzAccount | Out-Null
}
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

# Output structure
$timestamp   = (Get-Date).ToString("yyyyMMdd-HHmmss")
$bundleRoot  = Join-Path $OutputRoot "$($AutomationAccountName)_$timestamp"
$runbooksDir = Join-Path $bundleRoot "runbooks"
$pubDir      = Join-Path $runbooksDir "published"
$draftDir    = Join-Path $runbooksDir "draft"
$varsDir     = Join-Path $bundleRoot "variables"
$armDir      = Join-Path $bundleRoot "arm"

Ensure-Folder $bundleRoot
Ensure-Folder $runbooksDir
Ensure-Folder $pubDir
if ($IncludeDraftRunbooks) { Ensure-Folder $draftDir }
Ensure-Folder $varsDir
Ensure-Folder $armDir

# Export runbooks
Write-Host "Fetching runbooks..." -ForegroundColor Cyan
$runbooks = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName

$runbooksMetaPath = Join-Path $runbooksDir "runbooks.json"
$runbooks | Select-Object Name, RunbookType, Description, State, LogVerbose, LogProgress |
  ConvertTo-Json -Depth 5 | Out-File -FilePath $runbooksMetaPath -Encoding utf8

Write-Host ("Found {0} runbooks." -f ($runbooks | Measure-Object).Count) -ForegroundColor Green
Write-Host "Exporting Published runbooks (Export-AzAutomationRunbook -Slot Published)..." -ForegroundColor Cyan

foreach ($rb in $runbooks) {
  try {
    Export-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $rb.Name -Slot "Published" -OutputFolder $pubDir -Force | Out-Null

    Write-Host ("  ✔ Published exported: {0}" -f $rb.Name) -ForegroundColor Green
  } catch {
    Write-Warning ("  ✖ Published export failed for {0}: {1}" -f $rb.Name, $_.Exception.Message)
  }

  if ($IncludeDraftRunbooks) {
    try {
      Export-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $rb.Name -Slot "Draft" -OutputFolder $draftDir -Force | Out-Null

      Write-Host ("  ✔ Draft exported:     {0}" -f $rb.Name) -ForegroundColor Green
    } catch {
      Write-Warning ("  ⚠ Draft export skipped/failed for {0}: {1}" -f $rb.Name, $_.Exception.Message)
    }
  }
}

# Export variables
Write-Host ""
Write-Host "Fetching Automation variables..." -ForegroundColor Cyan
$vars = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName

$varsCsvPath = Join-Path $varsDir "automationVariables.csv"
$vars | Select-Object Name, Value, Encrypted, Description |
  Export-Csv -NoTypeInformation -Path $varsCsvPath -Encoding utf8

Write-Host ("Exported {0} variables to CSV: {1}" -f ($vars | Measure-Object).Count, $varsCsvPath) -ForegroundColor Green

# Generate ARM helper snippet for variables
Write-Host "Generating ARM variable resources snippet..." -ForegroundColor Cyan
$armVarResourcesPath = Join-Path $armDir "variables.resources.json"
$armVarParamsPath    = Join-Path $armDir "variables.parameters.json"

$resources = @()
$params = [ordered]@{ parameters = [ordered]@{} }

foreach ($v in $vars) {
  $isEnc = [bool]$v.Encrypted

  # encrypted value cannot be exported in plaintext; use parameter placeholder
  $valueField = $null
  if ($isEnc) {
    $paramName = "var_$($v.Name)"
    $valueField = "[parameters('$paramName')]"
    $params.parameters[$paramName] = [ordered]@{
      type = "string"
      metadata = [ordered]@{
        description = "Encrypted Automation variable '$($v.Name)'. Provide value securely at deployment time."
      }
    }
  } else {
    $valueField = (Escape-JsonString (($v.Value | Out-String).Trim()))
  }

  $resources += [ordered]@{
    type       = "Microsoft.Automation/automationAccounts/variables"
    apiVersion = "2022-08-08"
    name       = "[concat(parameters('automationAccountName'), '/$($v.Name)')]"
    properties = [ordered]@{
      description = (Escape-JsonString $v.Description)
      isEncrypted = $isEnc
      value       = $valueField
    }
  }
}

($resources | ConvertTo-Json -Depth 20) | Out-File -FilePath $armVarResourcesPath -Encoding utf8
($params    | ConvertTo-Json -Depth 20) | Out-File -FilePath $armVarParamsPath    -Encoding utf8

# README
$readmePath = Join-Path $bundleRoot "README.txt"
@"
Automation Migration Bundle (EXPORT)
====================================

Runbooks:
- runbooks\published\  (exported via Export-AzAutomationRunbook -Slot Published)
- runbooks\draft\      (optional if IncludeDraftRunbooks was used)

Variables:
- variables\automationVariables.csv
- arm\variables.resources.json     (ARM helper snippet)
- arm\variables.parameters.json    (parameters stub for encrypted variables)

Notes:
- Encrypted variable values are NOT exported. The ARM snippet uses parameters for encrypted values.
"@ | Out-File -FilePath $readmePath -Encoding utf8

Write-Host ""
Write-Host "DONE ✅ Bundle created at: $bundleRoot" -ForegroundColor Cyan