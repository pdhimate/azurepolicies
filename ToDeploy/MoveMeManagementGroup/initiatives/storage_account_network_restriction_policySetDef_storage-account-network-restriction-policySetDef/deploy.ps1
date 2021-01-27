# Get the path of Script that deploys the Initiative
# TODO: Check this while setting up CI/CD, possibly hard code/parametrize it
Write-Output "PSScriptRoot path: $PSScriptRoot"
$RootFolderPath = (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName
Write-Output "RootFolder path: $RootFolderPath"
$scriptPath = "$RootFolderPath\Scripts\DeployInitiative.ps1"
Write-Output "Deployment script path: $scriptPath"

# Set params for Initiative deployment
$splatParams = @{
    definitionFile      = "$PSScriptRoot/policySet.json";
    managementGroupName = "moveme-management-group";
    initiativeLocation  = "/providers/Microsoft.Management/managementGroups/moveme-management-group";
    PolicyLocations     = @{
        "restrict-public-ips-policyDef-Location" = "/providers/Microsoft.Management/managementGroups/moveme-management-group"
    }
}

# Deploy by invoking the Script with above parameters
& $scriptPath @splatParams
