<#
  .SYNOPSIS
    Deploy Initiative (policy set) definition.
  .DESCRIPTION
    This script deploys Azure Policy Initiative (policy set) definition.
  .PARAMETER DefinitionFile
    path to the Policy Initiative Definition file.
  .PARAMETER PolicyLocations
    When the policy initiative contains custom policies, instead of hardcoding the policy definition resource Id, use a string to represent the location (resource Id to a subscription or a management group where the policy definition resides.) and replace this string with the value specified in this parameter. See Example for detailed usage
  .PARAMETER subscriptionId
    When deploying the policy initiative definition to a subscription, specify the subscription Id.
  .PARAMETER managementGroupName
    When deploying the policy initiative definition to a management group, specify the management group name (not the display name).
  .EXAMPLE
    ./DeployInitiatives.ps1 -definitionFile C:\Temp\azurepolicyset.json -subscriptionId fd16c044-18c4-4abe-a908-1e0b79f45003
    Deploy a policy initiative definition to a subscription (interactive mode)
  .EXAMPLE
    ./DeployInitiative.ps1 -definitionFile C:\Temp\azurepolicyset.json -managementGroupName myMG 
    Deploy a policy initiative definition to a management group 
  .EXAMPLE
    ./DeployInitiative.ps1 -definitionFile C:\Temp\azurepolicyset.json -managementGroupName myMG -PolicyLocations @{policyLocationResourceId1 = '/providers/Microsoft.Management/managementGroups/MyMG'}
    Deploy a policy initiative definition to a management group and replace the policy location from the definition file as shown below:
    {
        "name": "storage-account-network-restriction-policySetDef",
        "properties": {
            "displayName": "My Initiative Name",
            "description": "This is a custom Initiative to restrict Storage Account access",
            "metadata": {
                "version" : "1.0.0.0",
                "category": "Custom"
            },
            "parameters": {},
            "policyDefinitions": [
                {
                    "policyDefinitionId": "{policyLocation1}/providers/Microsoft.Authorization/policyDefinitions/custom1-policyDef"
                },
                {
                    "policyDefinitionId": "{policyLocation2}/providers/Microsoft.Authorization/policyDefinitions/custom2-policyDef"
                }
            ]
        }
    }
#>

#Requires -Modules 'az.resources'
[CmdLetBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToSub', HelpMessage = 'Specify the file path for the policy initiative definition file.')]
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToMG', HelpMessage = 'Specify the file path for the policy initiative definition file.')]
    [ValidateScript( { test-path $_ })]
    [String]$definitionFile,

    # Specify this to dynamically replace "{policyLocation1}" 
    # and similar strings from the definition json file 
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = 'deployToSub', HelpMessage = 'Specify hashtable that contains policy definition locations that the script will find and replace from the policy set definition.')]
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = 'deployToMG', HelpMessage = 'Specify hashtable that contains policy definition locations that the script will find and replace from the policy set definition.')]
    [hashtable]$PolicyLocations, 

    [Parameter(Mandatory = $true, ParameterSetName = 'deployToSub')]
    [ValidateScript( { try { [guid]::parse($_) } catch { $false } })]
    [String]$subscriptionId,

    [Parameter(Mandatory = $true, ParameterSetName = 'deployToMG')]
    [ValidateNotNullOrEmpty()]
    [String]$managementGroupName,

    # Path of the node (Management Group or Subscription) where the Initiative definitions will be stored and assigned.
    # e.g. /providers/Microsoft.Management/managementGroups/moveme-management-group
    # e.g. /subscriptions/ffad927d-ae53-4617-a608-b0e8e7544bd2
    # policy.json will look like: {initiativeLocation}/providers/Microsoft.Authorization/policySetDefinitions/storage-account-network-restriction-policySetDef
    # this script will replace {initiativeLocation} with the specified value (like shown in e.g.)
    # If this is not being used just specify the value to be empty string OR do not use {initiativeLocation} in the policySet.json
    [Parameter(Mandatory = $true, ParameterSetName = 'deployToMG')]
    [Parameter(Mandatory = $true, ParameterSetName = 'deployToSub')]
    [String]$initiativeLocation
)

##########################################################
# Local functions start
##########################################################

# Deploys an Initiave (PolicySet)
function DeployInitiativeDefinition {
    [CmdLetBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToSub')]
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToMG')]
        [object]$Definition, # json definition object

        [Parameter(Mandatory = $true, ParameterSetName = 'deployToSub')]
        [String]$subscriptionId,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'deployToMG')]
        [String]$managementGroupName,

        [Hashtable] $Output
    )

    # Extract from policy definition, sinnce the cmdlet can not pick it up from the specified json file
    $policySetName = $Definition.name
    $policySetDisplayName = $Definition.properties.displayName
    $policySetDescription = $Definition.properties.description
    $policySetParameters = convertTo-Json -InputObject $Definition.properties.parameters -Depth 25
    $policySetDefinition = convertTo-Json -InputObject $Definition.properties.policyDefinitions -Depth 25
    $policySetMetaData = convertTo-Json -InputObject $Definition.properties.metadata -Depth 25
    
    Write-Output "Initiative Name: $policySetName"

    # Deploy to either Subcription or Management group
    if ($PSCmdlet.ParameterSetName -eq 'deployToSub') {
        Write-Output "Deploying Policy Initiative: '$policySetName' to Subscription: '$subscriptionId'"
    }
    else {
        Write-Output "Deploying Policy Initiative: '$policySetName' to Management Group: '$managementGroupName'"
    }
    
    # create deployment parameters hastable
    $deployParams = @{
        Name             = $policySetName
        DisplayName      = $policySetDisplayName
        Description      = $policySetDescription
        Parameter        = $policySetParameters
        PolicyDefinition = $policySetDefinition
        Metadata         = $policySetMetaData
    }
    Write-Output "  - 'DeployPolicySetDefinition' function parameter set name: '$($PSCmdlet.ParameterSetName)'"
    If ($PSCmdlet.ParameterSetName -eq 'deployToSub') {
        Write-Output "  - Adding SubscriptionId to the input parameters for New-AzPolicySetDefinition cmdlet"
        $deployParams.Add('SubscriptionId', $subscriptionId)
    }
    else {
        Write-Output "  - Adding ManagementGroupName to the input parameters for New-AzPolicySetDefinition cmdlet"
        $deployParams.Add('ManagementGroupName', $managementGroupName)
    }
    Write-Output "Initiative Definition:"
    Write-Output $policySetDefinition
    $deployResult = New-AzPolicySetDefinition @deployParams
    
    Write-Output "Deployed Initiative: $policySetName "
    
    # Set output
    if ($Output) {
        $Output.PolicyDefinitionId = $deployResult.PolicyDefinitionId
        $Output.PolicyName = $deployResult.ResourceName
        $Output.ResourceId = $deployResult.ResourceId
        $Output.Name = $deployResult.Name
    }
}

##########################################################
# Local functions end
##########################################################
# Init
$ErrorActionPreference = 'STOP'

# Global try
try {

    # Get sign-in context and init
    $context = Get-AzContext
    if (!$context) {
        Write-Error "You are not signed in/connected to Azure. Use Connect-AzAccount"
    }
    $currentTenantId = $context.Tenant.Id
    $currentSubId = $context.Subscription.Id
    $currentSubName = $context.Subscription.Name
    Write-Output "Connected to tenant '$currentTenantId', subscription '$currentSubName' ($currentSubId))"

    # Read Initiative definition file
    Write-Output "Reading Initiative Definition File: '$definitionFile'"
    $InitiativeDefinition = Get-Content -path $definitionFile -Raw

    # Replace policy definition location resource Ids, if any dynamic locations were supplied
    $dynamicPolicyLocationsSupplied = $PSBoundParameters.ContainsKey('PolicyLocations') -and $PolicyLocations -and $PolicyLocations.Count -gt 0
    if ($dynamicPolicyLocationsSupplied) {
        Write-Output "Replacing dynamic PolicyLocations in the Initiative Definition file"
        foreach ($key in $PolicyLocations.Keys) {
            $stringToReplace = "{$key}" # must be present in the Initiative def json file
            if ($InitiativeDefinition.Contains($stringToReplace)) {
                $InitiativeDefinition = $InitiativeDefinition.Replace($stringToReplace, $PolicyLocations.$key)
                Write-Output ("Replaced " + "$stringToReplace :" + $PolicyLocations.$key)
            }
        }
    }

    # Replace {initiativeLocation} with the specified one, if any
    Write-Output "Replacing {initiativeLocation} with $initiativeLocation"
    $stringToReplace = "{initiativeLocation}" # may be present in the PolicySet.json file
    if ($InitiativeDefinition.Contains($stringToReplace)) {
        $InitiativeDefinition = $InitiativeDefinition.Replace($stringToReplace, $initiativeLocation)
        Write-Output ("Replaced " + "$stringToReplace :" + $initiativeLocation)
    }
    
    # Validate definition content
    $InitiativeDefinitionJsonObj = Convertfrom-Json -InputObject $InitiativeDefinition
    Write-Output "Validating Initiative Definition"
    if ($InitiativeDefinitionJsonObj.properties.policyDefinitions) {
        Write-Output "'$definitionFile' is a policy initiative definition. It will be deployed."
    }
    elseif ($InitiativeDefinitionJsonObj.properties.policyRule) {
        Write-Error "'$definitionFile' contains a policy definition which is not supported by this script."
    }
    else {
        Write-Error "Unable to parse '$definitionFile'. It is not a policy or initiative definition file. Content unrecognised."
    }

    # Deploy Initiative
    $params = @{
        Definition = $InitiativeDefinitionJsonObj
    }
    if ($PSCmdlet.ParameterSetName -eq 'deployToSub') {
        $params.Add('subscriptionId', $subscriptionId)
    }
    else {
        $params.Add('managementGroupName', $managementGroupName)
    }
    $Output = New-Object -TypeName Hashtable
    $params.Add('Output', $Output)
    DeployInitiativeDefinition @params
    
    # Display output
    Write-Output "Deployment of Intiative complete"
}

# Global catch
catch {
    $errors = $_
    Write-Output "Something went wrong! Details below."
    Write-Output $errors
    Write-Error $errors # causes script to fail
}
