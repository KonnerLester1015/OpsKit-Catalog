<#
.SYNOPSIS
    Shows key details for an Entra ID user.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = 'User principal name (user@contoso.com)')]
    [string] $UserPrincipalName
)

$ScriptInfo = @{
    Name            = 'Entra User Details'
    Description     = 'Account status, sign-in, licences and manager for one user.'
    Version         = '0.1.0'
    Author          = 'KonnerLester1015'
    Tags            = @('entra', 'users', 'graph')
    RequiresModules = @('Microsoft.Graph.Users')
    RequiresAdmin   = $false
    Platforms       = @()
}

if (-not (Get-MgContext)) {
    Invoke-OpsKitTask 'Connecting to Microsoft Graph (a browser window may open)' {
        Connect-MgGraph -Scopes 'User.Read.All', 'AuditLog.Read.All' -NoWelcome
    }
}

$properties = 'DisplayName', 'UserPrincipalName', 'AccountEnabled', 'JobTitle', 'Department', 'CreatedDateTime', 'SignInActivity', 'AssignedLicenses'
$user = Invoke-OpsKitTask "Looking up $UserPrincipalName" {
    Get-MgUser -UserId $UserPrincipalName -Property $properties -ExpandProperty Manager
}

Show-OpsKitDetails -Title $user.DisplayName -InputObject ([ordered]@{
        UPN           = $user.UserPrincipalName
        Enabled       = [bool]$user.AccountEnabled
        'Job title'   = $user.JobTitle
        Department    = $user.Department
        Manager       = $user.Manager.AdditionalProperties.displayName
        Created       = $user.CreatedDateTime
        'Last sign-in' = $user.SignInActivity.LastSignInDateTime
        Licences      = @($user.AssignedLicenses).Count
    })
