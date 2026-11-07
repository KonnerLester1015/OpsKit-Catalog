<#
.SYNOPSIS
    Checks that the Varonis address is reachable from this machine.
.NOTES
    Starter script for the Varonis extension. It only tests the network path,
    no credentials are used. Real integrations will build on the saved address.
#>
[CmdletBinding()]
param(
    [string] $Url
)

$ScriptInfo = @{
    Name            = 'Test Varonis Connection'
    Description     = 'Check that Varonis is reachable and remember its address.'
    Version         = '0.1.0'
    Author          = 'KonnerLester1015'
    Tags            = @('varonis', 'connectivity', 'setup')
    RequiresModules = @()
    RequiresAdmin   = $false
    Platforms       = @()
}

# Remember the address between runs so users only type it once.
$saved = (Get-OpsKitConfig -Module 'Varonis').Url
if (-not $Url) {
    $Url = Read-OpsKitText 'Varonis URL' -Default ($saved ?? 'https://varonis.contoso.com') -Validate { $_ -match '^https?://' } -ValidationMessage 'Start with https://'
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

Write-OpsKitStatus "Varonis answered with HTTP $($result.'HTTP status') in $($result.'Latency ms') ms" -Level Success

if ($Url -ne $saved -and (Read-OpsKitConfirm "Save $Url as the Varonis address?" -Default $true)) {
    Set-OpsKitModuleSetting -Module 'Varonis' -Name 'Url' -Value $Url
    Write-OpsKitStatus 'Saved' -Level Success
}
