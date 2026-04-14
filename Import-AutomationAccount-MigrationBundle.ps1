<#
.SYNOPSIS
  Imports an Azure Automation migration bundle into a target Automation Account:
   - Runbooks: imports files -> creates Draft -> publishes
   - Variables: imports from CSV; encrypted variables must be provided via hashtable

.DESCRIPTION
  - Runbooks are imported using Import-AzAutomationRunbook, which imports as a DRAFT runbook. [1](https://microsoft-my.sharepoint.com/personal/sdibiaselutz_microsoft_com/_layouts/15/Doc.aspx?sourcedoc=%7B8557701A-FFAF-45D7-BD85-4E546343FE4F%7D&file=MS%20Agent365%20AI-CT-Requirements%20Updated%204-13-26_v2%20sml.xlsx&action=default&mobileredirect=true&DefaultItemOpen=1)
  - Then Publish-AzAutomationRunbook is called to make them runnable. [1](https://microsoft-my.sharepoint.com/personal/sdibiaselutz_microsoft_com/_layouts/15/Doc.aspx?sourcedoc=%7B8557701A-FFAF-45D7-BD85-4E546343FE4F%7D&file=MS%20Agent365%20AI-CT-Requirements%20Updated%204-13-26_v2%20sml.xlsx&action=default&mobileredirect=true&DefaultItemOpen=1)
  - Variables are imported using Set-AzAutomationVariable / New-AzAutomationVariable patterns.
  - Encrypted variable values are NOT pulled from CSV; you must provide them (securely). [2](https://learn.microsoft.com/en-us/powershell/module/az.automation/export-azautomationrunbook?view=azps-13.0.0)

.PARAMETER SubscriptionId
  Target subscription where the destination Automation Account exists.

.PARAMETER ResourceGroupName
  Target Resource Group.

.PARAMETER AutomationAccountName
  Target Automation Account name.

.PARAMETER BundleRoot
  Path to the exported bundle root folder (the folder that contains runbooks\ and variables\).

.PARAMETER PublishAfterImport
  If specified, publishes runbooks after import (recommended). Imported runbooks are Draft by default. [1](https://microsoft-my.sharepoint.com/personal/sdibiaselutz_microsoft_com/_layouts/15/Doc.aspx?sourcedoc=%7B8557701A-FFAF-45D7-BD85-4E546343FE4F%7D&file=MS%20Agent365%20AI-CT-Requirements%20Updated%204-13-26_v2%20sml.xlsx&action=default&mobileredirect=true&DefaultItemOpen=1)

.PARAMETER EncryptedVariableValues
  Hashtable of encrypted variable values: @{ "VarName" = "secretValue"; "AnotherVar"="..." }
  Provide these securely (e.g., from pipeline secret variables).

.EXAMPLE
  $enc = @{ "SQLPassword" = $env:SQLPassword }
  .\Import-AutomationAccount-MigrationBundle.ps1 `
    -SubscriptionId "00000000-0000-0000-0000-000000000000" `
    -ResourceGroupName "rg-target" `
    -AutomationAccountName "aa-target" `
    -BundleRoot ".\AutomationMigrationBundle\aa-legalhold_20260413-220000" `
    -PublishAfterImport `
    -EncryptedVariableValues $enc
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string] $SubscriptionId,

  [Parameter(Mandatory=$true)]
  [string] $ResourceGroupName,

  [Parameter(Mandatory=$true)]
  [string] $AutomationAccountName,

  [Parameter(Mandatory=$true)]
  [string] $BundleRoot,

  [Parameter()]
  [switch] $PublishAfterImport,

  [Parameter()]
  [hashtable] $EncryptedVariableValues = @{}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Module {
  param([Parameter(Mandatory=$true)][string]$Name)
  if (-not (Get-Module -ListAvailable -Name $Name)) {
    Write-Host "Installing module $Name..." -ForegroundColor Yellow
    Install-Module $Name -Scope CurrentUser -Force
  }
  Import-Module $Name -ErrorAction Stop
}

function Get-RunbookTypeFromExtension {
  param([Parameter(Mandatory=$true)][string]$Path)

  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()

  switch ($ext) {
    ".ps1"          { return "PowerShell" }
    ".py"           { return "Python3" }
    ".graphrunbook" { return "Graph" }
    default         { return "PowerShell" }
  }
}

Write-Host "== Azure Automation Migration Bundle Import ==" -ForegroundColor Cyan
Write-Host "Target SubscriptionId: $SubscriptionId"
Write-Host "Target ResourceGroup:  $ResourceGroupName"
Write-Host "Target AutomationAcct: $AutomationAccountName"
Write-Host "BundleRoot:            $BundleRoot"
Write-Host ""

# --- Modules ---
Ensure-Module "Az.Accounts"
Ensure-Module "Az.Automation"

# --- Login / context ---
if (-not (Get-AzContext)) {
  Write-Host "Connecting to Azure..." -ForegroundColor Yellow
  Connect-AzAccount | Out-Null
}
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

# --- Validate bundle structure ---
$publishedDir = Join-Path $BundleRoot "runbooks\published"
$varsCsvPath  = Join-Path $BundleRoot "variables\automationVariables.csv"

if (-not (Test-Path $publishedDir)) {
  throw "Published runbooks folder not found: $publishedDir"
}
if (-not (Test-Path $varsCsvPath)) {
  throw "Variables CSV not found: $varsCsvPath"
}

# --- Import Runbooks (Draft) then Publish ---
Write-Host "Importing runbooks (Published files -> Draft runbooks)..." -ForegroundColor Cyan
$runbookFiles = Get-ChildItem -Path $publishedDir -File

Write-Host ("Found {0} runbook files to import." -f ($runbookFiles | Measure-Object | Select-Object -ExpandProperty Count)) -ForegroundColor Green

foreach ($file in $runbookFiles) {
  $rbName = [IO.Path]::GetFileNameWithoutExtension($file.Name)
  $rbType = Get-RunbookTypeFromExtension -Path $file.FullName

  try {
    # Import creates/updates a DRAFT runbook. [1](https://microsoft-my.sharepoint.com/personal/sdibiaselutz_microsoft_com/_layouts/15/Doc.aspx?sourcedoc=%7B8557701A-FFAF-45D7-BD85-4E546343FE4F%7D&file=MS%20Agent365%20AI-CT-Requirements%20Updated%204-13-26_v2%20sml.xlsx&action=default&mobileredirect=true&DefaultItemOpen=1)
    Import-AzAutomationRunbook `
      -ResourceGroupName $ResourceGroupName `
      -AutomationAccountName $AutomationAccountName `
      -Name $rbName `
      -Type $rbType `
      -Path $file.FullName `
      -Force | Out-Null

    Write-Host ("  ✔ Imported (Draft): {0} [{1}]" -f $rbName, $rbType) -ForegroundColor Green

    if ($PublishAfterImport) {
      # Publish to make it runnable. [1](https://microsoft-my.sharepoint.com/personal/sdibiaselutz_microsoft_com/_layouts/15/Doc.aspx?sourcedoc=%7B8557701A-FFAF-45D7-BD85-4E546343FE4F%7D&file=MS%20Agent365%20AI-CT-Requirements%20Updated%204-13-26_v2%20sml.xlsx&action=default&mobileredirect=true&DefaultItemOpen=1)
      Publish-AzAutomationRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name $rbName | Out-Null

      Write-Host ("    ✔ Published:      {0}" -f $rbName) -ForegroundColor Green
    }
  }
  catch {
    Write-Warning ("  ✖ Runbook import/publish failed for {0}: {1}" -f $rbName, $_.Exception.Message)
  }
}

# --- Import Variables ---
# Variables are shared assets in an Automation account. [2](https://learn.microsoft.com/en-us/powershell/module/az.automation/export-azautomationrunbook?view=azps-13.0.0)
Write-Host ""
Write-Host "Importing Automation variables from CSV..." -ForegroundColor Cyan
$vars = Import-Csv -Path $varsCsvPath

Write-Host ("Found {0} variables in CSV." -f ($vars | Measure-Object | Select-Object -ExpandProperty Count)) -ForegroundColor Green

foreach ($v in $vars) {
  $name        = $v.Name
  $desc        = $v.Description
  $isEncrypted = $false

  # CSV might contain "True"/"False" strings
  if ($v.Encrypted -match "^(true|True|TRUE)$") { $isEncrypted = $true }

  try {
    # Determine value to set:
    # - For encrypted variables: require user-provided value via hashtable
    # - For non-encrypted: use CSV Value
    $valueToSet = $null

    if ($isEncrypted) {
      if ($EncryptedVariableValues.ContainsKey($name)) {
        $valueToSet = [string]$EncryptedVariableValues[$name]
      } else {
        Write-Warning ("  ⚠ Encrypted variable '{0}' skipped: no value provided in -EncryptedVariableValues." -f $name)
        continue
      }
    } else {
      $valueToSet = [string]$v.Value
    }

    # Create or update variable
    # If it exists, Set-AzAutomationVariable updates it; otherwise New-AzAutomationVariable creates it.
    $existing = $null
    try {
      $existing = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $name -ErrorAction Stop
    } catch { $existing = $null }

    if ($null -eq $existing) {
      New-AzAutomationVariable `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name $name `
        -Value $valueToSet `
        -Encrypted:$isEncrypted `
        -Description $desc | Out-Null
      Write-Host ("  ✔ Created variable: {0} (Encrypted={1})" -f $name, $isEncrypted) -ForegroundColor Green
    } else {
      Set-AzAutomationVariable `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name $name `
        -Value $valueToSet `
        -Encrypted:$isEncrypted `
        -Description $desc | Out-Null
      Write-Host ("  ✔ Updated variable: {0} (Encrypted={1})" -f $name, $isEncrypted) -ForegroundColor Green
    }
  }
  catch {
    Write-Warning ("  ✖ Variable import failed for {0}: {1}" -f $name, $_.Exception.Message)
  }
}

Write-Host ""
Write-Host "DONE. Import completed for bundle: $BundleRoot" -ForegroundColor Cyan

Write-Host ""
Write-Host "Notes:" -ForegroundColor Cyan
Write-Host "- Imported runbooks land as Draft; publish is required to run them." -ForegroundColor Gray
