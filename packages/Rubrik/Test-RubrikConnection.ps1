<#
.SYNOPSIS
    Checks that the Rubrik address is reachable from this machine.
.NOTES
    Starter script for the Rubrik extension. It only tests the network path,
    no credentials are used. Real integrations will build on the saved address.
#>
[CmdletBinding()]
param(
    [string] $Url
)

$ScriptInfo = @{
    Name            = 'Test Rubrik Connection'
    Description     = 'Check that Rubrik is reachable and remember its address.'
    Version         = '0.1.0'
    Author          = 'KonnerLester1015'
    Tags            = @('rubrik', 'connectivity', 'setup')
    RequiresModules = @()
    RequiresAdmin   = $false
    Platforms       = @()
}

# Remember the address between runs so users only type it once.
$saved = (Get-OpsKitConfig -Module 'Rubrik').Url
if (-not $Url) {
    $Url = Read-OpsKitText 'Rubrik URL' -Default ($saved ?? 'https://yourorg.my.rubrik.com') -Validate { $_ -match '^https?://' } -ValidationMessage 'Start with https://'
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

Write-OpsKitStatus "Rubrik answered with HTTP $($result.'HTTP status') in $($result.'Latency ms') ms" -Level Success

if ($Url -ne $saved -and (Read-OpsKitConfirm "Save $Url as the Rubrik address?" -Default $true)) {
    Set-OpsKitModuleSetting -Module 'Rubrik' -Name 'Url' -Value $Url
    Write-OpsKitStatus 'Saved' -Level Success
}
