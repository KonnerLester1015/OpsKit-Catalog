[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = 'Computer to check')]
    [string] $ComputerName
)

$ScriptInfo = @{
    Name            = 'Thing'
    Description     = 'Gets a thing.'
    Version         = (Get-Date).ToString('yyyy.M.d')
    Author          = 'octocat'
    Tags            = @('test')
    RequiresModules = @()
    RequiresAdmin   = $false
    Platforms       = @()
}

[pscustomobject]@{ ComputerName = $ComputerName }
