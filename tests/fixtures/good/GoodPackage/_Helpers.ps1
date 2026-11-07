function Get-FixtureService {
    [CmdletBinding()]
    param([string] $Name, [string] $State, [string[]] $ComputerName, [switch] $IncludeDisabled)
    [pscustomobject]@{ Name = $Name; State = $State; ComputerName = $ComputerName; IncludeDisabled = [bool]$IncludeDisabled }
}
