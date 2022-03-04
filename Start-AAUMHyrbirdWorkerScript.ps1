<#PSScriptInfo

.VERSION 
    0.1

.AUTHOR 

.COMPANYNAME 

.TAGS 
    UpdateManagement, Automation

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 
    External Variables  are defined in the automation account under shared resources tab. 
        UpdateManagement-RG
        UpdateManagement-AA
        UpdateManagement-HW
        
.RELEASENOTES

.SYNOPSIS
 Runs a child Automation Runbook on a hybrid worker

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It requires hybrid workers to be configured on the machines which need to run scripts locally.

.PARAMETER RunbookName
  The name of the Azure Automation runbook you wish to execute on the hybrid workers in a local context
  
.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.

#>

Param
(
    [Parameter(Mandatory = $true, Position = 0)][string]$RunbookName,
    [string]$SoftwareUpdateConfigurationRunContext
)

# Function used to determine when the child job has reached a terminal status
function IsJobTerminalState([string] $status) {
    return $status -eq "Completed" -or $status -eq "Failed" -or $status -eq "Stopped" -or $status -eq "Suspended"
}

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

# Retrieve automation account info from automation variables.
$resourceGroup = Get-AutomationVariable -Name 'UpdateManagement-RG'
$automationAccount = Get-AutomationVariable -Name 'UpdateManagement-AA'
$runOn = Get-AutomationVariable -Name 'UpdateManagement-HW'


# Create lists used when tracking and validating child runbook status
#$runStatus = New-Object System.Collections.Generic.List[System.Object]
#$finalStatus = New-Object System.Collections.Generic.List[System.Object]

# Convert run context from JSON before retrieving computer names
$context = ConvertFrom-Json  $SoftwareUpdateConfigurationRunContext

# The SoftwareUpdateConfigurationRunContext object can contain duplicate entries for machines.
# This can cause pre and post-scripts to run multiple times on the same machine.
# To work around this behavior, use Sort-Object -Unique to select only unique VM names in your script.
$ComputerNames = $Context.SoftwareUpdateConfigurationSettings.nonAzureComputerNames | Sort-Object -Unique

# Start runbook on each machine and add job object to the runStatus list.
$RunStatus=foreach ($ComputerName in $ComputerNames) {
    $params = @{"ComputerName" = $ComputerName;}
    Start-AzAutomationRunbook -AutomationAccountName $automationAccount -Name $RunbookName -ResourceGroupName $ResourceGroup -RunOn $runOn -Parameters $params -DefaultProfile $AzureContext
    #$runStatus.Add($output)
}

# Determine status of all runs.
$finalStatus = foreach ($RunningJob in $runStatus) {
    $currentStatus = $RunningJob | Get-AzAutomationJob
    $pollingSeconds = 15
    $maxTimeout = 1200
    $waitTime = 0
    # Wait until job is no longer running
    while ((IsJobTerminalState $currentStatus.Status) -eq $false -and $waitTime -lt $maxTimeout) {
        Start-Sleep -Seconds $pollingSeconds
        $waitTime += $pollingSeconds
        $currentStatus = $RunningJob | Get-AzAutomationJob
    }
    # Store job status to evaluate later
    $currentStatus
}

# Review the final status for all child jobs 
foreach ($Job in $finalStatus) {
    if ($Job.Status -ne "Completed") {
        # Write error with job details for reference
        Write-Error -Message ("Job Status: " + $Job.Status + " RunbookName: " + $Job.RunbookName + " HybridWorker: " + $Job.HybridWorker + " JobID: " + $Job.JobId)
        # Throwing an exception will cause the script to go into a failed state, which will cancel the update deployment.
        throw "Halting update management process"
    }
}