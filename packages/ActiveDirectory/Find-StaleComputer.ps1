<#
.SYNOPSIS
    Finds computer accounts that have not logged on for a number of days.
#>
[CmdletBinding()]
param(
    [int] $Days,
    [string] $SearchBase
)

$ScriptInfo = @{
    Name            = 'Stale Computers'
    Description     = 'Computer accounts with no logon in N days. Read-only report.'
    Version         = '0.1.0'
    Author          = 'KonnerLester1015'
    Tags            = @('computers', 'cleanup', 'report')
    RequiresModules = @()
    RequiresAdmin   = $false
    Platforms       = @('Windows')
}

# Optional inputs can still be asked for inside the script.
if (-not $Days) {
    $Days = [int](Read-OpsKitText 'No logon for how many days?' -Default 90 -Validate { $_ -match '^\d+$' } -ValidationMessage 'Enter a whole number.')
}

$cutoff = (Get-Date).AddDays(-$Days)
$params = @{
    Filter     = { LastLogonDate -lt $cutoff -and Enabled -eq $true }
    Properties = 'LastLogonDate', 'OperatingSystem', 'Description'
}
if ($SearchBase) { $params.SearchBase = $SearchBase }

$computers = Invoke-OpsKitTask "Finding computers inactive since $($cutoff.ToString('yyyy-MM-dd'))" { Get-ADComputer @params }

Write-OpsKitStatus "$(@($computers).Count) enabled computer(s) with no logon in $Days days" -Level Info
$computers | Sort-Object LastLogonDate | Select-Object Name, OperatingSystem, LastLogonDate, Description,
    @{ Name = 'OU'; Expression = { ($_.DistinguishedName -split ',', 2)[1] } }
