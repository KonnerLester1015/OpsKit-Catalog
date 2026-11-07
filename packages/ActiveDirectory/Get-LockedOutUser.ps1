<#
.SYNOPSIS
    Lists locked-out Active Directory accounts.
#>
[CmdletBinding()]
param(
    [string] $Server
)

$ScriptInfo = @{
    Name            = 'Locked-out Users'
    Description     = 'Find accounts that are currently locked out.'
    Version         = '0.1.0'
    Author          = 'KonnerLester1015'
    Tags            = @('users', 'lockout', 'helpdesk')
    RequiresModules = @()
    RequiresAdmin   = $false
    Platforms       = @('Windows')
}

$params = @{}
if ($Server) { $params.Server = $Server }

$users = Invoke-OpsKitTask 'Searching for locked-out accounts' {
    Search-ADAccount -LockedOut @params |
        Get-ADUser -Properties DisplayName, LockoutTime, Department, LastBadPasswordAttempt @params
}

$users = @($users)
if ($users.Count -eq 0) {
    Write-OpsKitStatus 'No locked-out accounts' -Level Success
    return
}

Write-OpsKitStatus "$($users.Count) locked-out account(s)" -Level Warning
$users | Sort-Object LockoutTime -Descending | Select-Object `
    SamAccountName, DisplayName, Department,
    @{ Name = 'Locked out'; Expression = { [datetime]::FromFileTime($_.LockoutTime).ToString('yyyy-MM-dd HH:mm') } },
    @{ Name = 'Last bad password'; Expression = { $_.LastBadPasswordAttempt } }
