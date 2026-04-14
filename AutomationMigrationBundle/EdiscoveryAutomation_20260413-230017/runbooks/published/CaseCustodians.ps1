param(
    [Parameter(Mandatory = $false)]
    [string] $CaseId,

    [Parameter(Mandatory = $false)]
    [string] $NoticeTemplateId = "",

    [Parameter(Mandatory = $false)]
    [int] $DueDays = 7
)

# ----------------------------
# Automation Account variables
# ----------------------------
$appID        = Get-AutomationVariable -Name "AppID"
$tenantId     = Get-AutomationVariable -Name "TenantId"
$clientSecret = Get-AutomationVariable -Name "ClientSecret"
$logicAppUrl  = Get-AutomationVariable -Name "LogicAppUrl"

# Optional fallback: if CaseId not passed as parameter, read from Automation Variable
if ([string]::IsNullOrWhiteSpace($CaseId)) {
    try {
        $CaseId = Get-AutomationVariable -Name "CaseId"
    } catch {
        throw "CaseId was not provided as a runbook parameter and Automation Variable 'CaseId' was not found."
    }
}

# ----------------------------
# Auth to Graph
# ----------------------------
$secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$spCred       = New-Object System.Management.Automation.PSCredential ($appID, $secureSecret)

Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $spCred -NoWelcome

# ----------------------------
# Build endpoints for ONE case
# ----------------------------
$caseUrl       = "https://graph.microsoft.com/beta/security/cases/ediscoveryCases/$CaseId"
$legalHoldsUrl = "https://graph.microsoft.com/beta/security/cases/ediscoveryCases/$CaseId/legalHolds"

# (Optional) Validate case exists / fetch display name for troubleshooting
$case = Invoke-MgGraphRequest -Method GET -Uri $caseUrl

# ----------------------------
# Retrieve holds + custodians
# ----------------------------
$custodians = @()
$holdIds    = @()

$legalHolds = (Invoke-MgGraphRequest -Method GET -Uri $legalHoldsUrl).value

foreach ($legalHold in $legalHolds) {
    $legalHoldId = $legalHold.id
    $holdIds += $legalHoldId

    $userSourcesUrl = "$legalHoldsUrl/$legalHoldId/userSources"
    $dataSrcs = (Invoke-MgGraphRequest -Method GET -Uri $userSourcesUrl).value

    foreach ($holdUser in $dataSrcs) {
        $userId = $holdUser.id

        # Pull UPN + manager
        $userDetails = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$userId"
        $manager     = $null

        try {
            $manager = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$userId/manager"
        } catch {
            # Some users may not have a manager object; keep it null/blank rather than failing the run
            $manager = $null
        }

        $custodians += [PSCustomObject]@{
            upn         = $userDetails.userPrincipalName
            displayName = $holdUser.displayName
            managerUpn  = if ($manager -and $manager.userPrincipalName) { $manager.userPrincipalName } else { "" }
        }
    }
}

$uniqueCustodians = $custodians | Where-Object { $_.upn } | Sort-Object upn -Unique

# If multiple holds exist, output them all (instead of only the last $LegalHoldId)
$jsonObject = [PSCustomObject]@{
    CaseId           = $CaseId
    HoldIds          = $holdIds
    NoticeTemplateId = $NoticeTemplateId
    DueDays          = $DueDays
    Custodians       = $uniqueCustodians
}

Write-Output ($jsonObject | ConvertTo-Json -Depth 6)

# ----------------------------
# OPTIONAL: invoke Logic App
# ----------------------------
# If you want the runbook to POST directly to your Logic App URL:
# Invoke-RestMethod -Method POST -Uri $logicAppUrl -ContentType "application/json" -Body ($jsonObject | ConvertTo-Json -Depth 6)
