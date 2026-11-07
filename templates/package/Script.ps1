<#
.SYNOPSIS
    Lists fixed disks that are low on free space.
.NOTES
    Rename this file to Verb-Noun.ps1 with an approved verb (run Get-Verb), for example
    Get-LowDiskSpace.ps1. Each script is one menu entry.

    Rules: return objects (OpsKit shows them as a table and offers CSV/JSON export), use the
    OpsKit helpers instead of Write-Host / Read-Host / Format-Table, keep Get-, Test- and Find-
    scripts read-only, and confirm with Read-OpsKitConfirm before changing anything.
#>
[CmdletBinding()]
param(
    # OpsKit prompts for mandatory parameters, using HelpMessage as the prompt text.
    # [ValidateSet('A', 'B')] turns the prompt into a pick list.
    [Parameter(Mandatory, HelpMessage = 'Computers to check')]
    [string[]] $ComputerName,

    # Optional parameters keep their default.
    [int] $MinimumFreePercent = 10
)

# Plain values only: no variables, commands or expressions. The catalog reads this without running the script.
$ScriptInfo = @{
    Name            = 'Low Disk Space'
    Description     = 'Fixed disks with less free space than a threshold.'
    Version         = '1.0.0'
    Author          = 'your-github-username'
    Tags            = @('disks', 'report')
    RequiresModules = @()                # modules this script needs on top of the package's
    RequiresAdmin   = $false
    Platforms       = @('Windows')       # @() means every platform
}

$threshold = $MinimumFreePercent

# Invoke-OpsKitForEach shows a progress bar and keeps going when one computer fails.
Invoke-OpsKitForEach -InputObject $ComputerName -Activity 'Checking disks' -ScriptBlock {
    $computer = $_
    Get-CimInstance -ComputerName $computer -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' |
        Where-Object { $_.Size -gt 0 -and ($_.FreeSpace / $_.Size * 100) -lt $threshold } |
        Select-Object @{ Name = 'Computer'; Expression = { $computer } }, DeviceID,
            @{ Name = 'Size GB'; Expression = { [math]::Round($_.Size / 1GB, 1) } },
            @{ Name = 'Free %'; Expression = { [math]::Round($_.FreeSpace / $_.Size * 100, 1) } }
}
