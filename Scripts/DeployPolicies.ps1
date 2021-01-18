<#
  .SYNOPSIS
    Deploy Azure Policy definitions in bulk.
  .DESCRIPTION
    This script deploys Azure Policy definitions in bulk. You can deploy one or more policy definitions by specifying the file paths, or all policy definitions in a folder by specifying a folder path.
  .PARAMETER DefinitionFile
    path to the Policy Definition file. Supports multiple paths using array.
  .PARAMETER FolderPath
    Path to a folder that contains one or more policy definition files.
  .PARAMETER Recurse
    Use this switch together with -FolderPath to deploy policy definitions in the folder and its sub folders (recursive).
  .PARAMETER subscriptionId
    When deploying policy definitions to a subscription, specify the subscription Id.
  .PARAMETER -managementGroupName
    When deploying policy definitions to a management group, specify the management group name (not the display name).
  .PARAMETER silent
    Use this switch to use the surpress login prompt. The script will use the current Azure context (logon session) and it will fail if currently not logged on. Use this switch when using the script in CI/CD pipelines.
  .EXAMPLE
    ./deployPolicies.ps1 -definitionFile C:\Temp\azurepolicy.json -subscriptionId cd45c044-18c4-4abe-a908-1e0b79f45003
    Deploys a single policy definition to a subscription (interactive mode)
  .EXAMPLE
    ./deployPolicies.ps1 -FolderPath C:\Temp -recurse -managementGroupName myMG -silent
    Deploys all the policy definitions in the specified folder and its sub-folders to a management group (silent mode, i.e. in a CI/CD pipeline)
#>

#Requires -Modules 'az.resources'

[CmdLetBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployFilesToSub', HelpMessage = 'Specify the file paths for the policy definition files.')]
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployFilesToMG', HelpMessage = 'Specify the file paths for the policy definition files.')]
    [ValidateScript( { test-path $_ })]
    [String[]]$definitionFile,

    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployDirToSub', HelpMessage = 'Specify the directory path that contains the policy definition files.')]
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployDirToMG', HelpMessage = 'Specify the directory path that contains the policy definition files.')]
    [ValidateScript( { test-path $_ -PathType 'Container' })] # must be a folder
    [String]$folderPath,

    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployDirToSub', HelpMessage = 'Get policy definition files from the $folderPath and its subfolders.')]
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployDirToMG', HelpMessage = 'Get policy definition files from the $folderPath and its subfolders.')]
    [Switch]$Recurse,

    [Parameter(Mandatory = $true, ParameterSetName = 'deployFilesToSub')]
    [Parameter(Mandatory = $true, ParameterSetName = 'deployDirToSub')]
    [ValidateScript( { try { [guid]::parse($_) } catch { $false } })] # must be a GUID
    [String]$subscriptionId,

    [Parameter(Mandatory = $true, ParameterSetName = 'deployFilesToMG')]
    [Parameter(Mandatory = $true, ParameterSetName = 'deployDirToMG')]
    [ValidateNotNullOrEmpty()] # must not be null or empty white space
    [String]$managementGroupName ,

    [Parameter(Mandatory = $false, ParameterSetName = 'deployDirToSub', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
    [Parameter(Mandatory = $false, ParameterSetName = 'deployDirToMG', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
    [Parameter(Mandatory = $false, ParameterSetName = 'deployFilesToSub', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
    [Parameter(Mandatory = $false, ParameterSetName = 'deployFilesToMG', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
    [Switch]$silent
)

##########################################################
# Local functions
##########################################################

# Deploys the policy definitions
function DeployPolicyDefinition {
    [CmdLetBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToSub')]
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToMG')]
        [object]$Definition, # JSON object of the Definition.json file

        [Parameter(Mandatory = $true, ParameterSetName = 'deployToSub')]
        [String]$subscriptionId,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'deployToMG')]
        [String]$managementGroupName
    )
    Write-Output "Starting deployment of all polices"

    # Extract Name, DisplayName, etc from policy definition
    # This is needed since the New-AzPolicyDefinition CMDLET is currently unable to pick them from policy.json file 
    $policyName = $Definition.name
    $policyDisplayName = $Definition.properties.displayName
    $policyDescription = $Definition.properties.description
    $policyParameters = $Definition.properties.parameters | convertTo-Json -Depth 25
    $PolicyRule = $Definition.properties.policyRule | convertTo-Json -Depth 25
    $policyMetaData = $Definition.properties.metadata | convertTo-Json -Depth 25
    
    # create deployment parameters hastable
    $deployParams = @{
        Name        = $policyName
        DisplayName = $policyDisplayName
        Description = $policyDescription
        Parameter   = $policyParameters
        Policy      = $PolicyRule
        Metadata    = $policyMetaData
    }

    # deploy to either subcription or Management group
    Write-Output "'DeployPolicyDefinition' function parameter set name: '$($PSCmdlet.ParameterSetName)'"
    if ($PSCmdlet.ParameterSetName -eq 'deployToSub') {
        Write-Output "Adding SubscriptionId to the input parameters for New-AzPolicyDefinition cmdlet"
        $deployParams.Add('SubscriptionId', $subscriptionId)
    }
    else {
        Write-Output "Adding ManagementGroupName to the input parameters for New-AzPolicyDefinition cmdlet"
        $deployParams.Add('ManagementGroupName', $managementGroupName)
    }
    $deployResult = New-AzPolicyDefinition @deployParams
    $deployResult

    Write-Output "Deployment of all polices complete"
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
        Write-Error "You are not signed in/connected to Azure."
    }
    $currentTenantId = $context.Tenant.Id
    $currentSubId = $context.Subscription.Id
    $currentSubName = $context.Subscription.Name
    Write-Output "Connected to tenant '$currentTenantId', subscription '$currentSubName' ($currentSubId))"

    # Read all definitions into an array
    if ($PSCmdlet.ParameterSetName -eq 'deployDirToMG' `
            -or $PSCmdlet.ParameterSetName -eq 'deployDirToSub') {
        Write-Output "Folder path: '$folderPath'"
        if ($Recurse) {
            Write-Output "Recursing through all *.json files in the folder and its sub-folders."
            $definitionFiles = (Get-ChildItem -Path $folderPath -File -Filter '*.json' -Recurse).FullName
            Write-Output "Found $($definitionFiles.count) *.json files"
        }
        else {
            Write-Output "Retrieving all *.json files in the folder."
            $definitionFiles = (Get-ChildItem -Path $folderPath -File -Filter '*.json').FullName
            Write-Output "Found $($definitionFiles.count) *.json files"
        }
    }
    $Definitions = @()
    foreach ($file in $definitionFiles) {
        Write-Output "Parsing '$file'..."
        $objDef = Get-Content -path $file | Convertfrom-Json
        if ($objDef.properties.policyDefinitions) {
            Write-Error "'$file' is a policy initiative definition which is not supported by this script."
        }
        elseif ($objDef.properties.policyRule) {
            Write-Output "'$file' contains a policy definition. It will be deployed."
            $Definitions += $objDef
        }
        else {
            Write-Output "Unable to parse '$file'. It is not a policy definition file. Content unrecognised."
        }
    }

    # Deploy definitions
    $arrDeployResults = @()
    Foreach ($objDef in $Definitions) {
        $params = @{
            Definition = $objDef
        }
        If ($PSCmdlet.ParameterSetName -eq 'deployDirToSub' -or $PSCmdlet.ParameterSetName -eq 'deployFilesToSub') {
            Write-Output "Deploying policy '$($objDef.name)' to subscription '$subscriptionId'"
            $params.Add('subscriptionId', $subscriptionId)
        }
        else {
            Write-Output "Deploying policy '$($objDef.name)' to management group '$managementGroupName'"
            $params.Add('managementGroupName', $managementGroupName)
        }
        $deployResult = DeployPolicyDefinition @params
        $arrDeployResults += $deployResult
    }
    $arrDeployResults
}

# Global catch
catch {
    Write-Error "Something went wrong! Details below."
    $_
}

