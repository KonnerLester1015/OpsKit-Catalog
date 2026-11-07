<#
.SYNOPSIS
    Home screen widget: the domain and domain controller this computer is using.
.NOTES
    Uses nltest (the Windows DC locator), so it works without RSAT.
#>

$WidgetInfo = @{
    Name            = 'Domain controller'
    Description     = 'Domain, DC and AD site this computer is using'
    RequiresModules = @()
    Platforms       = @('Windows')
    RefreshSeconds  = 300
}

$system = Get-CimInstance -ClassName Win32_ComputerSystem -Property PartOfDomain, Domain
if (-not $system.PartOfDomain) {
    return [ordered]@{
        Domain = @{ Text = 'Not domain joined'; Level = 'Muted' }
    }
}

$output = nltest "/dsgetdc:$($system.Domain)" 2>$null
if ($LASTEXITCODE -ne 0) {
    return [ordered]@{
        Domain = $system.Domain
        Status = @{ Text = 'No domain controller reachable'; Level = 'Error' }
    }
}

# nltest prints "Name: value" lines, e.g. "  DC: \\DC01.contoso.com".
$fields = @{}
foreach ($line in $output) {
    if ($line -match '^\s*([^:]+?)\s*:\s*(.+)$') { $fields[$Matches[1]] = $Matches[2] -replace '^\\\\' }
}

[ordered]@{
    Domain  = $system.Domain
    DC      = $fields['DC']
    Address = $fields['Address']
    Site    = $fields['Dc Site Name']
    Status  = @{ Text = 'Reachable'; Level = 'Success' }
}
