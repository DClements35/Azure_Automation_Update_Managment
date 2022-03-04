<#PSScriptInfo

.VERSION 
  0.1

.AUTHOR 

.COMPANYNAME 

.TAGS 
  Hyper-V, Magic

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES

.SYNOPSIS
 Resumes a Hypver-V Host and move previously owned rolesback over.  

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It requires hybrid workers to be configured on the machines which need to run scripts locally.

.PARAMETER ComputerName
  The name of the computer this script will run against. 
  
.PARAMETER Credentials
  The credentials used to authenticate against the computer on which the script is being ran against.  

#>

Param
(
    [Parameter(Mandatory = $true, Position = 0)][string]$ComputerName,
    [ValidateNotNull()][System.Management.Automation.PSCredential]$Credentials
)

$credentialName = 'AzureAutomationCredAccount' 

#Import the module to use the PSCredential Object
Import-Module Orchestrator.AssetManagement.Cmdlets -ErrorAction SilentlyContinue

#Gets the PS Credential object that contains a DSGG.COM AD Account
$Credentials = Get-AutomationPSCredential -Name $credentialName

#Resume the paused cluster node that is provided via $ComputerName variable & failbacks any previously owned roles. 
Invoke-Command -ComputerName $ComputerName -Credential $Credentials -ScriptBlock {
    Resume-ClusterNode -Name $using:ComputerName -Failback Immediate 
}