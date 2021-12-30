# Specify the parameters for the deployment 
$ArmTemplateUrl = "https://cmteststorageacct.file.core.windows.net/arm-templates/ARM/xp-resources/azuredeploy.json?sv=2020-10-02&st=2021-12-15T03%3A34%3A49Z&se=2021-12-16T03%3A34%3A49Z&sr=f&sp=r&sig=7NtZZpQAZIU7dN3Vgm09tQTI2DMQ4HVaI7PjbDSkJOI%3D"
$ArmParametersPath = ".\azuredeploy.parameters.json"
$licenseFilePath = ".\license.xml"

# Specify the certificate file path and password if you want to deploy Sitecore XP or XDB configurations
$certificateFilePath = $null 
$certificatePassword = $null
$certificateBlob = $null

$Name = "cm-test-arm"
$location = "westus"
$AzureSubscriptionId = "80e2f4cb-198c-49b1-ad82-da207799c3f9"

# read the contents of your Sitecore license file
$licenseFileContent = Get-Content -Raw -Encoding UTF8 -Path $licenseFilePath | Out-String

# read the contents of your authentication certificate
if ($certificateFilePath) {
  $certificateBlob = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($certificateFilePath))
}

#region Create Params Object
# license file needs to be secure string and adding the params as a hashtable is the only way to do it
$additionalParams = New-Object -TypeName Hashtable

$params = Get-Content $ArmParametersPath -Raw | ConvertFrom-Json

# foreach ($p in $params | Get-Member -MemberType *Property) {
#   $additionalParams.Add($p.Name, $params.$($p.Name).value)
# }
foreach ($p in $params.parameters | Get-Member -MemberType *Property) {
  $additionalParams.Add($p.Name, $params.parameters.$($p.Name).value)
}

#$additionalParams.Set_Item('licenseXml', $licenseFileContent)
$additionalParams.Set_Item('deploymentId', $Name)

# Inject Certificate Blob and Password into the parameters
if ($certificateBlob) {
  $additionalParams.Set_Item('authCertificateBlob', $certificateBlob)
}
if ($certificatePassword) {
  $additionalParams.Set_Item('authCertificatePassword', $certificatePassword)
}

#endregion

#region Service Principle Details

# By default this script will prompt you for your Azure credentials but you can update the script to use an Azure Service Principal instead by following the details at the link below and updating the four variables below once you are done.
# https://azure.microsoft.com/en-us/documentation/articles/resource-group-authenticate-service-principal/

$UseServicePrincipal = $false
$TenantId = "SERVICE_PRINCIPAL_TENANT_ID"
$ApplicationId = "SERVICE_PRINCIPAL_APPLICATION_ID"
$ApplicationPassword = "SERVICE_PRINCIPAL_APPLICATION_PASSWORD"

#endregion

try {
  #region Validate Resouce Group Name	

  Write-Host "Validating Resource Group Name..."
  if (!($Name -cmatch '^(?!.*--)[a-z0-9]{2}(|([a-z0-9\-]{0,37})[a-z0-9])$')) {
    Write-Error "Name should only contain lowercase letters, digits or dashes,
					 dash cannot be used in the first two or final character,
					 it cannot contain consecutive dashes and is limited between 2 and 40 characters in length!"
    Break;		
  }
		
  #endregion
	
  Write-Host "Setting Azure PowerShell session context..."

 	if ($UseServicePrincipal -eq $true) {
    #region Use Service Principle
    $secpasswd = ConvertTo-SecureString $ApplicationPassword -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($ApplicationId, $secpasswd)
    Connect-AzAccount -ServicePrincipal -Tenant $TenantId -Credential $mycreds
		
    Set-AzContext -SubscriptionId $AzureSubscriptionId -TenantId $TenantId
    #endregion
  }
  else {
    #region Use Manual Login
    try {
      Write-Host "Try"
      Set-AzContext -SubscriptionId $AzureSubscriptionId
    }
    catch {
      Write-Host "Catch"
      Connect-AzAccount
      Set-AzContext -SubscriptionId $AzureSubscriptionId   
    }
    #endregion		
  }
	
 	Write-Host "Check if resource group already exists..."
  $notPresent = Get-AzResourceGroup -Name $Name -ev notPresent -ea 0
	
  if (!$notPresent) {
    New-AzResourceGroup -Name $Name -Location $location
  }
	
  Write-Host "Starting ARM deployment..."        
  New-AzResourceGroupDeployment `
    -Name $Name `
    -ResourceGroupName $Name `
    -TemplateUri $ArmTemplateUrl `
    -TemplateParameterObject $additionalParams `
    -DeploymentDebugLogLevel All -Debug -Verbose
			
  Write-Host "Deployment Complete."
}
catch {
  Write-Error $_.Exception.Message
  Break 
}