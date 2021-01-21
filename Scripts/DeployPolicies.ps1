<#
  .SYNOPSIS
    Deploys Azure Policies. Ensure that you do a Connect-AzAccount before runnning.
  .DESCRIPTION
    This script deploys Azure Policy definitions in bulk. You can deploy one or more policy definitions by specifying the file paths, or all policy definitions in a folder by specifying a folder path.
    Names of the files must end with policy.json and names of the assignment values files (used for assignment) must end with policy.assignment.json
  .PARAMETER DefinitionFiles
    path (or comma separated paths) to the Policy Definition file(s). Supports multiple paths using array.
    Names of the files must end with policy.json
  .PARAMETER FolderPath
    Path to a folder that contains one or more policy definition files.
  .PARAMETER Recurse
    Use this switch together with -FolderPath to deploy policy definitions in the folder and its sub folders (recursive).
  .PARAMETER subscriptionId
    When deploying policy definitions to a subscription, specify the subscription Id.
  .PARAMETER -managementGroupName
    Use this switch to use the surpress login prompt. The script will use the current Azure context (logon session) and it will fail if currently not logged on. Use this switch when using the script in CI/CD pipelines.
  .EXAMPLE
    ./DeployPolicies.ps1 -definitionFiles C:\Temp\vmpolicy.json -subscriptionId fd15c016-18c4-4abe-a908-1e0b79f45003
    Deploys a single policy definition to a subscription 
  .EXAMPLE
    ./DeployPolicies.ps1 -FolderPath C:\Temp -recurse -managementGroupName myMG 
    Deploys all the policy definitions in the specified folder and its sub-folders to a management group 
#>

#Requires -Modules 'az.resources'

[CmdLetBinding()]
param (
    # Names of the files must end with policy.json
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployFilesToSub', HelpMessage = 'Specify the file paths for the policy definition files.')]
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployFilesToMG', HelpMessage = 'Specify the file paths for the policy definition files.')]
    [ValidateScript( { test-path $_ })]
    [String[]]$definitionFiles,

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
    [String]$managementGroupName,

    # Path of the node (Management Group or Subscription) where the Policy definitions will be stored and assigned.
    # This is also the Scope where the Policy would be assigned
    # e.g. /providers/Microsoft.Management/managementGroups/moveme-management-group
    # e.g. /subscriptions/ffad927d-ae53-4617-a608-b0e8e7544bd2
    # policy.json will look like: {policyLocation}/providers/Microsoft.Authorization/policyDefinitions/d2f5bb15-8bab-447a-8109-acac05f8ec88
    # this script will replace {policyLocation} with the specified value (like shown in e.g.)
    # If this is not to be used then specify the value to be empty string OR do not use {policyLocation} in the policy.json
    [Parameter(Mandatory = $true, ParameterSetName = 'deployFilesToMG')]
    [Parameter(Mandatory = $true, ParameterSetName = 'deployDirToMG')]
    [Parameter(Mandatory = $true, ParameterSetName = 'deployFilesToSub')]
    [Parameter(Mandatory = $true, ParameterSetName = 'deployDirToSub')]
    [String]$policyLocation
)

##########################################################
# Local functions start
##########################################################

# Deploys a policy definition
function DeployPolicyDefinition {
    [CmdLetBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToSub')]
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToMG')]
        [object]$Definition, # JSON object of the Definition.json file

        [Parameter(Mandatory = $true, ParameterSetName = 'deployToSub')]
        [String]$subscriptionId,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'deployToMG')]
        [String]$managementGroupName,

        [Hashtable] $Output
    )
    Write-Output "Starting deployment of policy"

    # Extract Name, DisplayName, etc from policy definition
    # This is needed since the New-AzPolicyDefinition CMDLET is currently unable to pick them from policy.json file 
    $policyName = $Definition.name
    $policyDisplayName = $Definition.properties.displayName
    $policyDescription = $Definition.properties.description
    $policyParameters = $Definition.properties.parameters | convertTo-Json -Depth 25
    $PolicyRule = $Definition.properties.policyRule | convertTo-Json -Depth 25
    $policyMetaData = $Definition.properties.metadata | convertTo-Json -Depth 25
    
    Write-Output "Policy Name: $policyName"
    
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
        Write-Output "Deploying to Subscription $subscriptionId"
        $deployParams.Add('SubscriptionId', $subscriptionId)
    }
    else {
        Write-Output "Deploying to ManagementGroup $managementGroupName"
        $deployParams.Add('ManagementGroupName', $managementGroupName)
    }
    $deployResult = New-AzPolicyDefinition @deployParams
    $deployResult

    Write-Output "Deployed policy named: $policyName "

    # Set output
    if ($Output) {
        $Output.PolicyDefinitionId = $deployResult.PolicyDefinitionId
        $Output.PolicyName = $deployResult.ResourceName
        $Output.ResourceId = $deployResult.ResourceId
        $Output.Name = $deployResult.Name
    }
}

function AssignPolicyDefinition {
    param (
        # Path of the node (Management Group or Subscription) where the Policy will be stored
        # This is also the Scope where the Policy would be assigned
        # e.g. /providers/Microsoft.Management/managementGroups/moveme-management-group
        # e.g. /subscriptions/ffad927d-ae53-4617-a608-b0e8e7544bd2
        [Parameter(Mandatory = $true)]
        [string]$PolicyLocation,
        [object]$AssignmentJsonObj, 
        [Hashtable]$Output
    )
    ## Validate mandatory values from policy.assignment.json 
    $policyDefinitionId = $AssignmentJsonObj.properties.policyDefinitionId
    if (!$policyDefinitionId) {
        Write-Error "policy.assignment.json file must contain a properties.policyDefinitionId property"
    }
    $scope = $AssignmentJsonObj.properties.scope
    if (!$scope) {
        Write-Error "policy.assignment.json file must contain a properties.scope property"
    }
    $enforcementMode = $AssignmentJsonObj.properties.enforcementMode
    if (!$enforcementMode) {
        Write-Error "policy.assignment.json file must contain a properties.enforcementMode property"
    }
    $name = $AssignmentJsonObj.name
    if (!$name) {
        Write-Error "policy.assignment.json file must contain a name property"
    }
    $displayName = $AssignmentJsonObj.properties.displayName
    if (!$displayName) {
        Write-Error "policy.assignment.json file must contain a properties.displayName property"
    }

    ## Optional values
    $notScopes = $AssignmentJsonObj.properties.notScopes # Array of strings with scopes to be excluded
    $parameters = $AssignmentJsonObj.properties.parameters    # Policy parameters values json obj
    $location = $AssignmentJsonObj.location    # ManagedIdentity Location, if any
    
    # Assigned Identity and Location
    $isSystemIdentity = $AssignmentJsonObj.identity.type -eq "SystemAssigned"
    if ($isSystemIdentity) {
        if (!$location) {
            Write-Error "policy.assignment.json file must contain a location property if it contains identity property"
        }
    }

    $locationStringToReplace = "{policyLocation}"
    if ($policyDefinitionId.Contains($locationStringToReplace)) {
        $policyDefinitionId = $policyDefinitionId.Replace($locationStringToReplace, $PolicyLocation)
        Write-Output "Replaced $stringToReplace with $PolicyLocation in Assignment"
    }

    # Locate the PolicyDefinition, use Where since the cmdlet returns all policies if it does not find a matching one
    Write-Output "Finding Policy: $policyDefinitionId"
    $policy = Get-AzPolicyDefinition -Id $policyDefinitionId | Where-Object { $_.PolicyDefinitionId -eq $policyDefinitionId }
    Write-Output "Found Policy: "
    $policy

    # Create params splat
    $assignmentParams = @{
        Name             = $name;
        DisplayName      = $displayName;
        Scope            = $scope;
        PolicyDefinition = $policy;
        Location         = $location;
    }
    # parameters obj must be converted to Hashtable
    $assignmentParams.PolicyParameterObject = ConvertPSObjectToHashtable $parameters

    # Set optional params which must not be specified if null or empty
    if ($isSystemIdentity) {
        $assignmentParams.AssignIdentity = $true
    }
    if ($notScopes) { 
        $assignmentParams.NotScope = $notScopes
    }

    # Assign policy
    Write-Output "Creating Assignment with parameters:" 
    $assignmentParams
    $assignment = New-AzPolicyAssignment @assignmentParams
    Write-Output "Assignment complete: "
    $assignment

    # Set output
    if ($Output) {
        $Output.Assignment = $assignment
    }
}

function ConvertPSObjectToHashtable {
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $collection = @(
            foreach ($object in $InputObject) { ConvertPSObjectToHashtable $object }
        )

        Write-Output -NoEnumerate $collection
    }
    elseif ($InputObject -is [psobject]) {
        $hash = @{}

        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertPSObjectToHashtable $property.Value
        }

        $hash
    }
    else {
        $InputObject
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

    # Read files from current folder and subfodlers, if recursive flag was specified
    if ($PSCmdlet.ParameterSetName -eq 'deployDirToMG' `
            -or $PSCmdlet.ParameterSetName -eq 'deployDirToSub') {
        Write-Output "Folder path: '$folderPath'"
        if ($Recurse) {
            Write-Output "Recursing through all *.json files in the folder and its sub-folders."
            $definitionFiles = (Get-ChildItem -Path $folderPath -File -Filter '*policy.json' -Recurse).FullName
            Write-Output "Found $($definitionFiles.count) *policy.json files"
        }
        else {
            Write-Output "Retrieving all *.json files in the folder."
            $definitionFiles = (Get-ChildItem -Path $folderPath -File -Filter '*policy.json').FullName
            Write-Output "Found $($definitionFiles.count) *policy.json files"
        }
    }
   
    # Update, Validate and Read all definitions into an array
    $Definitions = @()
    Write-Output "Validating Policy Definition files"
    foreach ($file in $definitionFiles) {
        Write-Output "Parsing '$file'..."
        $rawFile = Get-Content -path $file -Raw 
        
        # Replace {policyLocation} in policy.json with the specified one, if any
        Write-Output "Replacing {policyLocation} with $policyLocation in policy.json"
        $stringToReplace = "{policyLocation}" # may be present in the *policy.json file
        if ($rawFile.Contains($stringToReplace)) {
            $rawFile = $rawFile.Replace($stringToReplace, $policyLocation)
            Write-Output ("Replaced " + "$stringToReplace :" + $policyLocation)
        }
       
        # Try to get all adjacent assignment files
        $folder = Split-Path -parent $file
        $assignmentFiles = (Get-ChildItem -Path $folder -File -Filter '*policy.assignment.json').FullName
        $assignmentDefJsonObjs = @()
        foreach ($assignmentFile in $assignmentFiles) {
            
            # Read assignment file
            $rawAssignment = $null
            if ([System.IO.File]::Exists($assignmentFile)) {
                $rawAssignment = Get-Content -path $assignmentFile -Raw
            }
            if (!$rawAssignment) {
                continue
            }

            # Replace {policyLocation} in policy.assignment.json with the specified one, if any
            Write-Output "Replacing {policyLocation} with $policyLocation in policy.assignment.json"
            $stringToReplace = "{policyLocation}" # may be present in the *policy.assignment.json file
            if ($rawAssignment.Contains($stringToReplace)) {
                $rawAssignment = $rawAssignment.Replace($stringToReplace, $policyLocation)
                Write-Output ("Replaced " + "$stringToReplace :" + $policyLocation)
            }

            # Convert to json obj and store in array 
            $assignmentDefJsonObj = Convertfrom-Json -InputObject $rawAssignment
            $assignmentDefJsonObjs += $assignmentDefJsonObj
        } 
        
        # Validate contents 
        $objDef = Convertfrom-Json -InputObject $rawFile
        if ($objDef.properties.policyDefinitions) {
            Write-Error "'$file' is a policy initiative definition which is not supported by this script."
        }
        elseif ($objDef.properties.policyRule) {
            Write-Output "'$file' contains a policy definition"
            $def = @{
                PolicyDefJsonObj = $objDef;
            }
            if ($assignmentDefJsonObjs.Count -gt 0) {
                Write-Output "'$file' contains a policy assignment file(s) adjacent, as a sibling"
                $def.AssignmentDefJsonObjs = $assignmentDefJsonObjs
            }
            $Definitions += $def
        }
        else {
            Write-Error "Unable to parse '$file'. It is not a policy definition file. Content unrecognised."
        }
    }

    # Deploy definitions
    $deployOutputs = @()
    $deployedCount = 0;
    $assignedCount = 0;
    foreach ($def in $Definitions) {
        
        # Deploy definition
        $params = @{
            Definition = $def.PolicyDefJsonObj
        }
        if ($PSCmdlet.ParameterSetName -eq 'deployDirToSub' -or $PSCmdlet.ParameterSetName -eq 'deployFilesToSub') {
            Write-Output "Deploying policy '$($def.name)' to subscription '$subscriptionId'"
            $params.Add('subscriptionId', $subscriptionId)
        }
        else {
            Write-Output "Deploying policy '$($def.name)' to management group '$managementGroupName'"
            $params.Add('managementGroupName', $managementGroupName)
        }
        $PolicyOutput = New-Object -TypeName Hashtable
        $params.Add('Output', $PolicyOutput)
        DeployPolicyDefinition @params
        
        # Create output
        $Output = @{
            PolicyOutput      = $PolicyOutput;
            AssignmentOutputs = @();
        }
        $deployedCount++

        # Assign definitions, if any assignment file(s) were found
        foreach ($assignmentDefJsonObj in $def.AssignmentDefJsonObjs) {
            $assignmentOutput = New-Object -TypeName Hashtable
            AssignPolicyDefinition -PolicyLocation $policyLocation `
                -AssignmentJsonObj $assignmentDefJsonObj `
                -Output $assignmentOutput

            $Output.AssignmentOutputs += $assignmentOutput
            $assignedCount++
        }

        $deployOutputs += $Output
        Write-Output "Deployed $deployedCount Policies and Assigned $assignedCount Policies so far."
    }

    # Display output
    Write-Output "Deployment of Policies complete"
}

# Global catch
catch {
    $errors = $_
    Write-Output "Something went wrong! Details below."
    Write-Output $errors
    Write-Error $errors # causes script to fail
}

