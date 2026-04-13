# =====================================================
# INTERACTIVE INPUT
# =====================================================

$TenantId = Read-Host "Enter Tenant ID"
$ClientId = Read-Host "Enter Client ID"
$ClientSecretSecure = Read-Host "Enter Client Secret" -AsSecureString
$ClientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecretSecure)
)

$TenantName = (Read-Host "Enter sharepoint Domain Name (Example: contoso)").ToLower()
$SiteAlias  = (Read-Host "Enter Site Alias (Example: legalhold)").ToLower()
$OwnerEmail= (Read-Host "What is Your Email Address").ToLower()




# =====================================================
# AUTHENTICATE
# =====================================================

$TokenBody = @{
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    Client_Id     = $ClientId
    Client_Secret = $ClientSecret
}

$TokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -ContentType "application/x-www-form-urlencoded" -Body $TokenBody

$AccessToken = $TokenResponse.access_token

$Headers = @{
    Authorization = "Bearer $AccessToken"
    "Content-Type" = "application/json"
}


$SPTokenBody = @{
                 grant_type    = "client_credentials"
                 client_id     = $ClientId
                 client_secret = $ClientSecret
                 scope         = "https://$TenantName.sharepoint.com/.default"
}

$SPTokenResponse = Invoke-RestMethod -Method Post  -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -ContentType "application/x-www-form-urlencoded"  -Body $SPTokenBody

$SPAccessToken = $SPTokenResponse.access_token


function Wait-ForListReady($ListName){

                                        Write-Host "Waiting for $ListName provisioning..."

                                        $Ready = $false

                                        while(-not $Ready){

                                                          $CheckUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists"
                                                          $Result=Invoke-RestMethod -Method GET -Uri $CheckUrl -Headers $Headers
                                                          
                                                          $ListFound = $Result.value | Where-Object { $_.displayName -eq $ListName }                                            
                                                          
                                                          if($ListFound){
                                                                          $Ready = $true
                                                                          Write-Host "$ListName Ready ✅"
                                                                         }
                                                          else{
                                                                 Write-Host "$ListName still provisioning..."
                                                                 Start-Sleep -Seconds 5
                                                                }


                                                           }
        
        }
         




# =====================================================
# CHECK IF SITE EXISTS
# =====================================================

$SiteLookupUri = "https://graph.microsoft.com/v1.0/sites/$TenantName.sharepoint.com:/sites/$SiteAlias"

try {
    $Site = Invoke-RestMethod -Uri $SiteLookupUri -Headers $Headers -Method GET
    Write-Host "✅ Site Already Exists"
}
catch {

    Write-Host "❗ Site NOT Found - Creating LegalHold Site..."

    Write-Host "Creating LegalHold Site..."                 
                      
    $SiteBody = @{
                   name = "LegalHold"
                   webUrl = "https://$TenantName.sharepoint.com/sites/$SiteAlias"
                   locale = "en-US"
                   shareByEmailEnabled = $false
                   description = "Legal Hold Site"
                   template = "sts"
                   ownerIdentityToResolve = @{
                                              email = $OwnerEmail
                                             }
                 } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/beta/sites" -Headers $Headers -Body $SiteBody
    Write-Host "⏳ Waiting for SharePoint Site Provisioning..."

                $Provisioned = $false
                while (-not $Provisioned) {

                                            try {
                                                   $Site = Invoke-RestMethod -Uri $SiteLookupUri -Headers $Headers -Method GET

                                                   if ($Site.id) {
                                                                   $Provisioned = $true
                                                                    Write-Host "✅ Site Ready"
                                                                 }
                                                }
                                            catch {
                                                      Write-Host "Still Provisioning ⏳..."
                                                      Start-Sleep -Seconds 15
                                                        }
                                          }
    
}

# =====================================================
# GET SITE ID AFTER CREATION
# =====================================================



$Site = Invoke-RestMethod -Uri $SiteLookupUri -Headers $Headers -Method GET
$SiteId = $Site.id


Write-Host "✅ Site Ready"



# =====================================================
# CREATE LIST FUNCTION
# =====================================================

function CreateList($Name,$Body){

    $CheckUri = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists?`$filter=displayName eq '$Name'"
    $Existing = Invoke-RestMethod -Uri $CheckUri -Headers $Headers -Method GET

    if($Existing.value.Count -gt 0){
        Write-Host "$Name Exists - Skipping"
        return
    }

    Invoke-RestMethod -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists" -Headers $Headers -Body ($Body | ConvertTo-Json -Depth 10)

    Write-Host "✅ $Name Created"
}

# =====================================================
# LEGALHOLDCOMMUNICATIONS
# =====================================================

$LegalHold = @{
 displayName="LegalHoldCommunications"
 columns=@(
   @{name="CaseID";text=@{}},
   @{name="CustodianName";text=@{}},
   @{name="AckDueDate";dateTime=@{}},
   @{name="Contact";text=@{}},  
   @{
     name="NoticeType"
     choice=@{
       allowTextEntry=$false
       choices=@("1st Notice","2nd Notice","3rd Notice")
     }
   },   
   @{
     name="UserApproved"
     choice=@{
       allowTextEntry=$false
       choices=@("Yes","No")
     }
   },
   @{name="ManagerName";text=@{}},
   @{name="NoticeSentDate";dateTime=@{}}
 )
 list=@{template="genericList"}
 OnQuickLaunch = $true
}

CreateList "LegalHoldCommunications" $LegalHold


# =====================================================
# CUSTODIANACKNOWLEDGEMENTS
# =====================================================

$Custodian = @{
 displayName="CustodianAcknowledgements"
 columns=@(
   @{name="AckId";text=@{}},
   @{name="CaseId";text=@{}},
   @{name="CustodianUPN";text=@{}},
   @{name="CustodianDisplayName";text=@{}},  
   @{
     name="AckStatus"
     choice=@{
       allowTextEntry=$false
       choices=@("Pending","Acknowledged")
             }
     },
   @{name="NoticeSentUtc";dateTime=@{}},
   @{name="AckedUtc";dateTime=@{}},
   @{name="AckedByUPN";text=@{}},
   @{name="AckedByDisplayName";text=@{}},   
   @{
     name="AckMethod"
     choice=@{
              allowTextEntry=$false
              choices=@("Portal","Email","Web")
             }
     },
   @{name="HoldID";text=@{}}
 )
 list=@{template="genericList"}
 OnQuickLaunch = $true
}

CreateList "CustodianAcknowledgements" $Custodian

Write-Host ""
Write-Host "🎉 SITE + LISTS DEPLOYED SUCCESSFULLY 🎉"


