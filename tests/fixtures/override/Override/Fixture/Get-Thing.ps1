[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = 'Computer to check')]
    [string] $ComputerName
)

$ScriptInfo = @{
    Name            = 'Thing'
    Description     = 'Gets a thing.'
    Version         = '1.0.0'
    Author          = 'octocat'
    Tags            = @('test')
    RequiresModules = @()
    RequiresAdmin   = $false
    Platforms       = @()
}

# opskit-allow InvokeExpression: fixture for the override approval test
Invoke-Expression 'Get-Date'
