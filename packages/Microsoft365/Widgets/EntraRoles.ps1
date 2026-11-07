<#
.SYNOPSIS
    Home screen widget: the current Microsoft Graph sign-in and your active Entra roles.
.NOTES
    Widgets never sign in. This only reads a Graph session that a script already
    opened in this OpsKit window. PIM activations show how long they have left.
    Reading role assignments needs RoleManagement.Read.Directory (or Directory.Read.All).
#>

$WidgetInfo = @{
    Name            = 'Entra ID'
    Description     = 'Graph sign-in and your active Entra roles'
    RequiresModules = @('Microsoft.Graph.Authentication')
    Platforms       = @()
    RefreshSeconds  = 120
}

# If the Graph module isn't loaded yet there can't be a session, and loading it just to check is slow.
$context = if (Get-Module -Name Microsoft.Graph.Authentication) { Get-MgContext } else { $null }
if (-not $context) {
    return [ordered]@{ Graph = @{ Text = 'Not connected'; Level = 'Muted' } }, 'Run a Microsoft 365 script to sign in.'
}

$rows = [ordered]@{
    Account = if ($context.Account) { $context.Account } else { "$($context.AppName) (app)" }
    Tenant  = $context.TenantId
}
if ($context.AuthType -ne 'Delegated') {
    $rows.Roles = @{ Text = 'Signed in as an app, no user roles'; Level = 'Muted' }
    return $rows
}

function Format-TimeLeft([datetime] $End) {
    $left = $End.ToUniversalTime() - [datetime]::UtcNow
    if ($left.TotalMinutes -lt 1) { return 'ending' }
    if ($left.TotalHours -lt 1) { return '{0}m left' -f [int]$left.TotalMinutes }
    '{0}h {1}m left' -f [int][math]::Floor($left.TotalHours), $left.Minutes
}

try {
    $me = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/me?$select=id'
    $filter = "principalId eq '$($me.id)'"
    $active = @((Invoke-MgGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleAssignmentScheduleInstances?`$filter=$filter&`$expand=roleDefinition").value)

    $rows.Roles = if ($active.Count) {
        foreach ($assignment in $active | Sort-Object { $_.roleDefinition.displayName }) {
            $name = $assignment.roleDefinition.displayName
            if ($assignment.assignmentType -eq 'Activated' -and $assignment.endDateTime) {
                @{ Text = "$name · $(Format-TimeLeft $assignment.endDateTime)"; Level = 'Warning' }
            }
            else { $name }
        }
    }
    else { @{ Text = 'None active'; Level = 'Muted' } }

    try {
        $eligible = @((Invoke-MgGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleEligibilityScheduleInstances?`$filter=$filter").value)
        $inactive = @($eligible | Where-Object { $_.roleDefinitionId -notin $active.roleDefinitionId }).Count
        if ($inactive) { $rows.Eligible = @{ Text = "$inactive more you can activate in PIM"; Level = 'Muted' } }
    }
    catch { Write-Verbose "Skipping eligible roles: $_" }   # eligibility needs extra permissions; skip quietly
}
catch {
    # Fallback that needs fewer permissions but can't tell PIM activations apart.
    $roles = @((Invoke-MgGraphRequest -Method GET -Uri 'v1.0/me/memberOf/microsoft.graph.directoryRole?$select=displayName').value)
    $rows.Roles = if ($roles.Count) { @($roles.displayName | Sort-Object) } else { @{ Text = 'None active'; Level = 'Muted' } }
}

$rows
