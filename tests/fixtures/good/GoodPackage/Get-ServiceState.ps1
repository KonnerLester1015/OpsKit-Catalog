<#
.SYNOPSIS
    Mentions Invoke-Expression and Write-Host in a comment, which is allowed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = 'Service name')]
    [string] $Name,

    [Parameter(Mandatory, HelpMessage = 'Which state to report')]
    [ValidateSet('Running', 'Stopped')]
    [string] $State,

    [string[]] $ComputerName,

    [switch] $IncludeDisabled
)

$ScriptInfo = @{
    Name            = 'Service State'
    Description     = 'Services in a given state.'
    Version         = '1.2.3'
    Author          = 'octocat'
    Tags            = @('services')
    RequiresModules = @()
    RequiresAdmin   = $true
    Platforms       = @('Windows')
}

. (Join-Path $PSScriptRoot '_Helpers.ps1')
Get-FixtureService -Name $Name -State $State -ComputerName $ComputerName -IncludeDisabled:$IncludeDisabled
