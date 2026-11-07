<#
.SYNOPSIS
    Checks that the CrowdStrike Falcon address is reachable from this machine.
.NOTES
    Starter script for the CrowdStrike Falcon extension. It only tests the network path,
    no credentials are used. Real integrations will build on the saved address.
#>
[CmdletBinding()]
param(
    [string] $Url
)

$ScriptInfo = @{
    Name            = 'Test CrowdStrike Falcon Connection'
    Description     = 'Check that CrowdStrike Falcon is reachable and remember its address.'
    Version         = '0.1.0'
    Author          = 'KonnerLester1015'
    Tags            = @('crowdstrike', 'connectivity', 'setup')
    RequiresModules = @()
    RequiresAdmin   = $false
    Platforms       = @()
}

# Remember the address between runs so users only type it once.
$saved = (Get-OpsKitConfig -Module 'CrowdStrike').Url
if (-not $Url) {
    $Url = Read-OpsKitText 'CrowdStrike Falcon URL' -Default ($saved ?? 'https://api.crowdstrike.com') -Validate { $_ -match '^https?://' } -ValidationMessage 'Start with https://'
}

$result = Invoke-OpsKitTask "Contacting $Url" {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec 10 -SkipHttpErrorCheck -ErrorAction Stop
    [pscustomobject]@{
        Url           = $Url
        'HTTP status' = [int]$response.StatusCode
        'Latency ms'  = $timer.ElapsedMilliseconds
    }
}

Write-OpsKitStatus "CrowdStrike Falcon answered with HTTP $($result.'HTTP status') in $($result.'Latency ms') ms" -Level Success

if ($Url -ne $saved -and (Read-OpsKitConfirm "Save $Url as the CrowdStrike Falcon address?" -Default $true)) {
    Set-OpsKitModuleSetting -Module 'CrowdStrike' -Name 'Url' -Value $Url
    Write-OpsKitStatus 'Saved' -Level Success
}
