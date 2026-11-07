<#
.SYNOPSIS
    Home screen widget: vCenter / ESXi servers PowerCLI is connected to in this window.
.NOTES
    Reads PowerCLI's $global:DefaultVIServers. Never connects by itself.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Reads the PowerCLI connection list.')]
param()

$WidgetInfo = @{
    Name            = 'vCenter'
    Description     = 'Servers PowerCLI is connected to'
    RequiresModules = @()
    Platforms       = @()
    RefreshSeconds  = 120
}

$servers = @($global:DefaultVIServers | Where-Object { $_.IsConnected })
if ($servers.Count -eq 0) {
    return [ordered]@{ vCenter = @{ Text = 'Not connected'; Level = 'Muted' } }, 'Run a VMware script to connect.'
}

$rows = [ordered]@{}
foreach ($server in $servers) {
    $rows[$server.Name] = @{ Text = "$($server.User) · v$($server.Version)"; Level = 'Success' }
}
$rows
