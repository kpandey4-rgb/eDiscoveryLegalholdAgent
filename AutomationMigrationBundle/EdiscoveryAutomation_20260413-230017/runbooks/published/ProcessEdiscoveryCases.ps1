
# Get variables from Automation Account
$appID        = Get-AutomationVariable -Name "AppID"
$tenantId     = Get-AutomationVariable -Name "TenantId"
$clientSecret = Get-AutomationVariable -Name "ClientSecret"
$logicAppUrl  = Get-AutomationVariable -Name "LogicAppUrl"


# Convert plain client secret string to SecureString
$secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$spCred       = New-Object System.Management.Automation.PSCredential ($appID, $secureSecret)


#Authenticate using the parameter set supported by your module version
Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $spCred -NoWelcome


# Define endpoints and variables
$eCases = "https://graph.microsoft.com/beta/security/cases/ediscoveryCases"
$NoticeTemplateId = ""
$DueDays = 7

# Fetch eDiscovery cases
$cases = (Invoke-MgGraphRequest -Method GET -Uri $eCases).value

$custodians = @()

foreach ($case in $cases) {
    if (($case.Status -eq 'active') -and ($case.displayName -notlike '*content*')) {
        $caseId = $case.id
        $custodianUrl = "https://graph.microsoft.com/beta/security/cases/ediscoveryCases/$caseId/legalHolds"
        $LegalHolds = (Invoke-MgGraphRequest -Method GET -Uri $custodianUrl).value

        foreach ($LegalHold in $LegalHolds) {
            $LegalHoldId = $LegalHold.id
            $dataSrcUrl = "$custodianUrl/$LegalHoldId/userSources"
            $dataSrcs = (Invoke-MgGraphRequest -Method GET -Uri $dataSrcUrl).value

            foreach ($holdUser in $dataSrcs) {
                $UserId = $holdUser.id
                $userDetails = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId"
                $manager = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/manager"

                $custodian = [PSCustomObject]@{
                    upn         = $userDetails.userPrincipalName
                    displayName = $holdUser.displayName
                    managerUpn  = $manager.userPrincipalName
                }
                $custodians += $custodian
            }
        }

        $uniqueCustodians = $custodians | Sort-Object upn -Unique

        $jsonObject = [PSCustomObject]@{
            CaseId           = $caseId
            HoldId           = $LegalHoldId
            NoticeTemplateId = $NoticeTemplateId
            DueDays          = $DueDays
            Custodians       = $uniqueCustodians
        }

        $jsonOutput = $jsonObject | ConvertTo-Json -Depth 3
        Write-Output ($jsonObject | ConvertTo-Json -Depth 6)
    }
}
