# ===============================
# Azure Automation Variables
# ===============================
$appID        = Get-AutomationVariable -Name "AppID"
$tenantId     = Get-AutomationVariable -Name "TenantId"
$clientSecret = Get-AutomationVariable -Name "ClientSecret"

# ===============================
# Authenticate to Microsoft Graph
# ===============================
$secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$spCred       = New-Object System.Management.Automation.PSCredential ($appID, $secureSecret)

Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $spCred -NoWelcome

# ===============================
# Graph Endpoint – ACTIVE cases only
# ===============================
$casesUrl = "https://graph.microsoft.com/beta/security/cases/ediscoveryCases"

# ===============================
# Retrieve ALL active cases (pagination safe)
# ===============================
$activeCases = @()
$nextLink = $casesUrl

do {
    $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink
    $activeCases += $response.value
    $nextLink = $response.'@odata.nextLink'
} while ($nextLink)

# ===============================
# Shape output for Copilot Studio (Variant B)
# ===============================
$activeCasesSlim = $activeCases | Select-Object id,displayName,status,lastModifiedDateTime

# ===============================
# OUTPUT (JSON ONLY – Copilot Safe)
# ===============================
$activeCasesSlim | ConvertTo-Json -Depth 5