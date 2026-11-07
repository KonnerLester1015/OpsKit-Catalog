<#
.SYNOPSIS
    Lists VM snapshots older than a number of days.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Reads the PowerCLI connection list.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = 'vCenter server')]
    [string] $Server,

    [int] $OlderThanDays = 3
)

$ScriptInfo = @{
    Name            = 'Snapshot Report'
    Description     = 'Find VM snapshots older than N days, with size and creator.'
    Version         = '0.1.0'
    Author          = 'KonnerLester1015'
    Tags            = @('vmware', 'snapshots', 'report')
    RequiresModules = @()
    RequiresAdmin   = $false
    Platforms       = @()
}

if (-not ($global:DefaultVIServers | Where-Object Name -eq $Server)) {
    $credential = Get-Credential -Message "Credentials for $Server"
    Invoke-OpsKitTask "Connecting to $Server" { Connect-VIServer -Server $Server -Credential $credential -ErrorAction Stop | Out-Null }
}

$cutoff = (Get-Date).AddDays(-$OlderThanDays)
$snapshots = Invoke-OpsKitTask 'Collecting snapshots' {
    Get-VM -Server $Server | Get-Snapshot | Where-Object Created -lt $cutoff
}

Write-OpsKitStatus "$(@($snapshots).Count) snapshot(s) older than $OlderThanDays days" -Level Info
$snapshots | Sort-Object Created | Select-Object VM, Name,
    @{ Name = 'Created'; Expression = { $_.Created.ToString('yyyy-MM-dd') } },
    @{ Name = 'Age (days)'; Expression = { [int]((Get-Date) - $_.Created).TotalDays } },
    @{ Name = 'Size GB'; Expression = { [math]::Round($_.SizeGB, 1) } },
    Description
