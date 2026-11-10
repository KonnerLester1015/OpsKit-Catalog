#Requires -Version 7.4
<#
.SYNOPSIS
    Validates the packages in packages/ and builds the OpsKit Catalog site.

.DESCRIPTION
    Reads every package folder, checks it against the catalog rules and, when everything passes,
    writes the static site: catalog.json, one zip per package, the raw source files and the pages
    from site-src/.

    Package code is never executed. Metadata is read from the PowerShell AST with SafeGetValue(),
    which only accepts plain values.

.PARAMETER OutputPath
    Folder to write the site to. It is deleted and recreated, so it must be empty or a folder
    this script created before.

.PARAMETER PackagesPath
    Folder that holds the package folders. Defaults to packages/ next to build/.

.PARAMETER BaseUrl
    Absolute URL the site is served from, with a trailing slash. Defaults to the GitHub Pages URL
    derived from GITHUB_REPOSITORY (in Actions) or from the git remote.

.PARAMETER RepoUrl
    GitHub repository URL used for source and issue links. Defaults to the Actions environment,
    then the git remote.

.PARAMETER BaseRef
    Git ref to compare against (for example origin/main). When set, every package with changed
    files must have a higher Version than it had at the merge base.

.PARAMETER ValidateOnly
    Validate and build catalog.json in memory, but write nothing.

.PARAMETER RequireOverrideApproval
    Treat banned-pattern overrides as errors. CI sets this unless a maintainer added the
    "override-approved" label to the pull request.

.PARAMETER SkipAnalyzer
    Skip PSScriptAnalyzer (faster local runs). CI never skips it.

.PARAMETER SummaryPath
    Markdown summary file. Defaults to GITHUB_STEP_SUMMARY.

.PARAMETER PassThru
    Return the result object (issues, catalog) to the pipeline.

.EXAMPLE
    ./build/Build-Catalog.ps1 -OutputPath site

.EXAMPLE
    ./build/Build-Catalog.ps1 -ValidateOnly -BaseRef origin/main
#>
[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path $PSScriptRoot '..' 'site'),
    [string] $PackagesPath = (Join-Path $PSScriptRoot '..' 'packages'),
    [string] $BaseUrl,
    [string] $RepoUrl,
    [string] $Branch = 'main',
    [string] $BaseRef,
    [switch] $ValidateOnly,
    [switch] $RequireOverrideApproval,
    [switch] $SkipAnalyzer,
    [string] $SummaryPath = $env:GITHUB_STEP_SUMMARY,
    [switch] $PassThru
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$PackagesPath = [IO.Path]::GetFullPath($PackagesPath)
$SemVerPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
$Utf8NoBom = [Text.UTF8Encoding]::new($false)
$StrictUtf8 = [Text.UTF8Encoding]::new($false, $true)

$Rules = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'rules.psd1')
$Categories = @((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'categories.json') -Raw | ConvertFrom-Json).categories)
$ApprovedVerbs = @(Get-Verb | ForEach-Object Verb)

$Issues = [System.Collections.Generic.List[object]]::new()
$Overrides = [System.Collections.Generic.List[object]]::new()

# Which summary check each rule belongs to.
$CheckOf = @{}
foreach ($r in 'ModuleManifestMissing', 'ManifestParseError', 'ManifestNotPlain', 'ManifestFieldMissing', 'ManifestFieldInvalid',
    'ManifestFieldUnknown', 'InvalidCategory', 'InvalidVersion', 'InvalidPackageId', 'DuplicatePackageId', 'NoScripts', 'StrayFile') { $CheckOf[$r] = 'Package metadata (module.psd1, id)' }
foreach ($r in 'ScriptInfoMissing', 'ScriptInfoNotPlain', 'ScriptInfoFieldMissing', 'ScriptInfoFieldInvalid', 'ScriptInfoFieldUnknown',
    'WidgetInfoMissing', 'WidgetInfoNotPlain', 'WidgetInfoFieldMissing', 'WidgetInfoFieldInvalid', 'WidgetInfoFieldUnknown',
    'InvalidScriptName', 'InvalidWidgetName', 'ParameterHelpMessage', 'ReadOnlyScript') { $CheckOf[$r] = 'Script and widget metadata' }
$CheckOf['ParseError'] = 'Scripts parse without errors'
$CheckOf['PSScriptAnalyzer'] = 'PSScriptAnalyzer'
foreach ($r in @($Rules.BannedPatterns.Id) + 'OverrideNeedsApproval', 'OverrideMissingReason') { $CheckOf[$r] = 'Banned patterns' }
foreach ($r in 'FileTypeNotAllowed', 'BinaryFile', 'InvalidEncoding', 'PackageTooLarge', 'SymlinkNotAllowed') { $CheckOf[$r] = 'File types and size' }
$CheckOf['VersionNotBumped'] = 'Version bumped when files change'
$CheckOf['SchemaInvalid'] = 'catalog.json matches the schema'
$AllChecks = @($CheckOf.Values | Sort-Object -Unique)

#region Helpers

function Add-Issue {
    param(
        [ValidateSet('Error', 'Warning')] [string] $Severity = 'Error',
        [string] $Package,
        [string] $File,
        [int] $Line,
        [Parameter(Mandatory)] [string] $Rule,
        [Parameter(Mandatory)] [string] $Message
    )
    $Issues.Add([pscustomobject]@{
            Severity = $Severity
            Package  = $Package
            File     = $File
            Line     = $Line
            Rule     = $Rule
            Message  = $Message
        })
}

function Get-DisplayPath([string] $Path) {
    # Relative to the Actions workspace when there is one, so annotations land on the right file.
    $base = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { $RepoRoot }
    [IO.Path]::GetRelativePath($base, $Path).Replace('\', '/')
}

function Test-StringList($Value) {
    if ($null -eq $Value -or $Value -is [string]) { return $true }
    if ($Value -isnot [array]) { return $false }
    foreach ($item in $Value) { if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) { return $false } }
    $true
}

function Get-StringList($Value) {
    # The comma keeps PowerShell from unrolling the array when it is returned.
    if ($null -eq $Value) { return , [string[]]@() }
    , [string[]]@($Value)
}

function Test-SingleLine([string] $Value, [int] $MaxLength) {
    -not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch '[\r\n]' -and $Value.Length -le $MaxLength
}

function Get-HashtableValue {
    <# Finds a top-level `$Name = @{ ... }` assignment and returns its plain values. #>
    param(
        [System.Management.Automation.Language.ScriptBlockAst] $Ast,
        [string] $Name
    )
    $assignments = @($Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -eq $Name
            }, $true))
    if ($assignments.Count -eq 0) { return @{ Status = 'Missing'; Message = "No `$$Name hashtable found." } }

    $top = @($assignments | Where-Object { $null -ne $Ast.EndBlock -and $_.Parent -eq $Ast.EndBlock })
    if ($top.Count -eq 0) {
        return @{ Status = 'NotPlain'; Line = $assignments[0].Extent.StartLineNumber; Message = "`$$Name must be assigned at the top level of the script, not inside a block or function." }
    }
    if ($assignments.Count -gt 1) {
        return @{ Status = 'NotPlain'; Line = $assignments[1].Extent.StartLineNumber; Message = "`$$Name is assigned more than once. Assign it once." }
    }

    $assignment = $top[0]
    $right = $assignment.Right
    if ($right -is [System.Management.Automation.Language.PipelineAst] -and $right.PipelineElements.Count -eq 1) { $right = $right.PipelineElements[0] }
    $hashtable = $null
    if ($assignment.Operator -eq 'Equals' -and
        $right -is [System.Management.Automation.Language.CommandExpressionAst] -and
        $right.Expression -is [System.Management.Automation.Language.HashtableAst]) {
        $hashtable = $right.Expression
    }
    if (-not $hashtable) {
        return @{ Status = 'NotPlain'; Line = $assignment.Extent.StartLineNumber; Message = "`$$Name must be a plain hashtable literal: `$$Name = @{ ... }" }
    }
    try {
        $value = $hashtable.SafeGetValue()
    }
    catch {
        return @{ Status = 'NotPlain'; Line = $assignment.Extent.StartLineNumber; Message = "`$$Name must contain plain values only (strings, numbers, `$true/`$false, @() arrays), no variables or commands. $($_.Exception.Message)" }
    }
    @{ Status = 'Ok'; Line = $assignment.Extent.StartLineNumber; Value = $value }
}

function Read-DataFile {
    <# Parses a .psd1 data file (or its text) and returns its hashtable without running it. #>
    param([string] $Path, [string] $Text)
    $tokens = $null; $errors = $null
    $ast = if ($PSBoundParameters.ContainsKey('Text')) {
        [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    }
    else {
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    }
    if ($errors.Count) { return @{ Status = 'ParseError'; Errors = $errors } }

    $statements = @(if ($ast.EndBlock) { $ast.EndBlock.Statements })
    $expression = if ($statements.Count -eq 1 -and $statements[0] -is [System.Management.Automation.Language.PipelineAst] -and
        $statements[0].PipelineElements.Count -eq 1 -and
        $statements[0].PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $statements[0].PipelineElements[0].Expression
    }
    if ($expression -isnot [System.Management.Automation.Language.HashtableAst] -or $ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock) {
        return @{ Status = 'NotPlain'; Message = 'The file must contain a single hashtable: @{ ... }' }
    }
    try { @{ Status = 'Ok'; Value = $expression.SafeGetValue() } }
    catch { @{ Status = 'NotPlain'; Message = "Use plain values only (strings, @() arrays, `$true/`$false). $($_.Exception.Message)" } }
}

function Test-MetadataFields {
    <# Checks a $ScriptInfo / $WidgetInfo hashtable. Returns a normalised copy. #>
    param(
        [hashtable] $Value,
        [string] $Kind,          # ScriptInfo or WidgetInfo
        [string[]] $Required,
        [string[]] $Optional,
        [string] $Package,
        [string] $File,
        [int] $Line
    )
    $known = $Required + $Optional
    foreach ($key in $Required) {
        if (-not $Value.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$Value[$key])) {
            Add-Issue -Package $Package -File $File -Line $Line -Rule "${Kind}FieldMissing" -Message "`$$Kind is missing the required field '$key'."
        }
    }
    foreach ($key in $Value.Keys) {
        if ($key -notin $known) {
            Add-Issue -Severity Warning -Package $Package -File $File -Line $Line -Rule "${Kind}FieldUnknown" -Message "`$$Kind has an unknown field '$key'. Known fields: $($known -join ', ')."
        }
    }

    $invalid = { param($k, $why) Add-Issue -Package $Package -File $File -Line $Line -Rule "${Kind}FieldInvalid" -Message "`$$Kind.$k $why" }
    foreach ($key in 'Name', 'Description', 'Author') {
        if ($Value.ContainsKey($key) -and $null -ne $Value[$key]) {
            $max = if ($key -eq 'Description') { 200 } else { 80 }
            if ($Value[$key] -isnot [string] -or -not (Test-SingleLine $Value[$key] $max)) { & $invalid $key "must be a single line of text, at most $max characters." }
        }
    }
    if ($Value.ContainsKey('Version') -and $Value['Version'] -notmatch $SemVerPattern) { & $invalid 'Version' "must be a semantic version such as '1.0.0' (found '$($Value['Version'])')." }
    foreach ($key in 'Tags', 'RequiresModules', 'Platforms') {
        if ($Value.ContainsKey($key) -and -not (Test-StringList $Value[$key])) { & $invalid $key "must be a string or an array of strings: @('a', 'b')." }
    }
    if ($Value.ContainsKey('Platforms') -and (Test-StringList $Value['Platforms'])) {
        foreach ($p in (Get-StringList $Value['Platforms'])) {
            if ($p -cnotin $Rules.Platforms) { & $invalid 'Platforms' "contains '$p'. Use $($Rules.Platforms -join ', '), or @() for all platforms." }
        }
    }
    if ($Value.ContainsKey('RequiresAdmin') -and $Value['RequiresAdmin'] -isnot [bool]) { & $invalid 'RequiresAdmin' 'must be $true or $false.' }
    if ($Value.ContainsKey('RefreshSeconds') -and $null -ne $Value['RefreshSeconds'] -and
        ($Value['RefreshSeconds'] -isnot [int] -or $Value['RefreshSeconds'] -lt 5)) { & $invalid 'RefreshSeconds' 'must be a whole number of seconds, at least 5.' }
}

function Get-ScriptParameter {
    param([System.Management.Automation.Language.ScriptBlockAst] $Ast, [string] $Package, [string] $File)
    $list = [System.Collections.Generic.List[object]]::new()
    if (-not $Ast.ParamBlock) { return , $list }
    foreach ($parameter in $Ast.ParamBlock.Parameters) {
        $type = 'object'; $mandatory = $false; $help = $null; $set = $null
        foreach ($attribute in $parameter.Attributes) {
            if ($attribute -is [System.Management.Automation.Language.TypeConstraintAst]) {
                $type = $attribute.TypeName.FullName
                continue
            }
            $attributeName = $attribute.TypeName.Name -replace '^System\.Management\.Automation\.' -replace 'Attribute$'
            if ($attributeName -eq 'Parameter') {
                foreach ($argument in $attribute.NamedArguments) {
                    switch ($argument.ArgumentName) {
                        'Mandatory' { if ($argument.ExpressionOmitted -or ($(try { $argument.Argument.SafeGetValue() } catch { $false }) -eq $true)) { $mandatory = $true } }
                        'HelpMessage' { $help = try { [string]$argument.Argument.SafeGetValue() } catch { $null } }
                    }
                }
            }
            elseif ($attributeName -eq 'ValidateSet') {
                $set = [string[]]@(foreach ($a in $attribute.PositionalArguments) { try { [string]$a.SafeGetValue() } catch { } })
            }
        }
        if ($mandatory -and [string]::IsNullOrWhiteSpace($help)) {
            Add-Issue -Severity Warning -Package $Package -File $File -Line $parameter.Extent.StartLineNumber -Rule 'ParameterHelpMessage' `
                -Message "Mandatory parameter `$$($parameter.Name.VariablePath.UserPath) has no HelpMessage. OpsKit uses it as the prompt text."
        }
        $entry = [ordered]@{
            name        = $parameter.Name.VariablePath.UserPath
            type        = $type
            mandatory   = $mandatory
            helpMessage = $help
        }
        if ($set) { $entry.validateSet = $set }
        $list.Add($entry)
    }
    , $list
}

function Test-BannedPattern {
    <# Runs the banned-pattern regexes over code with comments blanked out. #>
    param([string] $Text, $Tokens, [string] $Package, [string] $File)

    $chars = $Text.ToCharArray()
    $allowed = @{}   # line number -> list of overrides that apply to it
    foreach ($token in $Tokens) {
        if ($token.Kind -ne 'Comment') { continue }
        for ($i = $token.Extent.StartOffset; $i -lt $token.Extent.EndOffset -and $i -lt $chars.Length; $i++) {
            if ($chars[$i] -ne "`n" -and $chars[$i] -ne "`r") { $chars[$i] = ' ' }
        }
        if ($token.Text -match '(?i)opskit-allow\s+([A-Za-z]+(?:\s*,\s*[A-Za-z]+)*)\s*(?::\s*(.*?))?\s*(?:#>)?\s*$') {
            $ruleIds = @($Matches[1] -split '\s*,\s*')
            $reason = if ($Matches.Count -gt 2) { $Matches[2] } else { '' }
            $line = $token.Extent.StartLineNumber
            if ([string]::IsNullOrWhiteSpace($reason) -or $reason.Trim().Length -lt 10) {
                Add-Issue -Package $Package -File $File -Line $line -Rule 'OverrideMissingReason' `
                    -Message "Override for $($ruleIds -join ', ') needs a reason of at least 10 characters: # opskit-allow $($ruleIds[0]): <why this is safe>"
                continue
            }
            $override = [pscustomobject]@{ Package = $Package; File = $File; Line = $line; Rules = $ruleIds; Reason = $reason.Trim(); Used = $false }
            foreach ($l in $line, ($line + 1)) {
                if (-not $allowed.ContainsKey($l)) { $allowed[$l] = [System.Collections.Generic.List[object]]::new() }
                $allowed[$l].Add($override)
            }
        }
    }
    $code = [string]::new($chars)

    # Start offset of every line, to turn a match index into a line number.
    $lineStarts = [System.Collections.Generic.List[int]]::new()
    $lineStarts.Add(0)
    for ($i = 0; $i -lt $code.Length; $i++) { if ($code[$i] -eq "`n") { $lineStarts.Add($i + 1) } }

    foreach ($rule in $Rules.BannedPatterns) {
        foreach ($match in [regex]::Matches($code, $rule.Pattern)) {
            $index = $lineStarts.BinarySearch($match.Index)
            $line = if ($index -ge 0) { $index + 1 } else { -$index - 1 }
            $override = if ($allowed.ContainsKey($line)) { $allowed[$line] | Where-Object { $rule.Id -in $_.Rules } | Select-Object -First 1 }
            if ($override) {
                if (-not $override.Used) {
                    $override.Used = $true
                    $Overrides.Add($override)
                    $severity = if ($RequireOverrideApproval) { 'Error' } else { 'Warning' }
                    Add-Issue -Severity $severity -Package $Package -File $File -Line $line -Rule 'OverrideNeedsApproval' `
                        -Message "$($rule.Id) is allowed by an override ('$($override.Reason)'). A maintainer must approve it with the 'override-approved' label."
                }
                continue
            }
            $found = $match.Value.Trim()
            if ($found.Length -gt 60) { $found = $found.Substring(0, 57) + '...' }
            Add-Issue -Package $Package -File $File -Line $line -Rule $rule.Id -Message "$($rule.Message) Found: $found"
        }
    }
}

function New-ZipBytes {
    <# Builds a deterministic zip (sorted entries, fixed timestamps, '/' separators) in memory. #>
    param([string] $SourcePath, [string] $RootName, [string[]] $RelativePaths, [datetime] $Timestamp)
    $stream = [IO.MemoryStream]::new()
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        $sorted = [string[]]@($RelativePaths)
        [Array]::Sort($sorted, [StringComparer]::Ordinal)
        foreach ($relative in $sorted) {
            $entry = $zip.CreateEntry("$RootName/$relative", [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = [DateTimeOffset]::new([datetime]::SpecifyKind($Timestamp.Date, 'Unspecified'), [TimeSpan]::Zero)
            $bytes = [IO.File]::ReadAllBytes((Join-Path $SourcePath $relative))
            $entryStream = $entry.Open()
            try { $entryStream.Write($bytes, 0, $bytes.Length) } finally { $entryStream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
    , $stream.ToArray()
}

function Get-Sha256([byte[]] $Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertTo-UrlPath([string] $Path) {
    ($Path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
}

function Invoke-Git([string] $WorkingDirectory, [string[]] $Arguments) {
    $output = & git -C $WorkingDirectory @Arguments 2>$null
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

function ConvertTo-AnnotationText([string] $Value, [switch] $Property) {
    $Value = $Value.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    if ($Property) { $Value = $Value.Replace(':', '%3A').Replace(',', '%2C') }
    $Value
}

#endregion

#region URLs

$HasGit = [bool](Get-Command git -ErrorAction Ignore)

if (-not $RepoUrl) {
    if ($env:GITHUB_REPOSITORY) {
        $RepoUrl = "$(if ($env:GITHUB_SERVER_URL) { $env:GITHUB_SERVER_URL } else { 'https://github.com' })/$env:GITHUB_REPOSITORY"
    }
    elseif ($HasGit) {
        $remote = (Invoke-Git $RepoRoot @('remote', 'get-url', 'origin')).Output | Select-Object -First 1
        if ($remote -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$') {
            $RepoUrl = "https://github.com/$($Matches.owner)/$($Matches.repo)"
        }
    }
    if (-not $RepoUrl) { $RepoUrl = 'https://github.com/OWNER/opskit-catalog' }
}
$RepoUrl = $RepoUrl.TrimEnd('/')

if (-not $BaseUrl) {
    if ($RepoUrl -match '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)$') {
        $owner = $Matches.owner.ToLowerInvariant()
        $BaseUrl = if ($Matches.repo -ieq "$owner.github.io") { "https://$owner.github.io/" } else { "https://$owner.github.io/$($Matches.repo)/" }
    }
    else { $BaseUrl = 'http://localhost:8080/' }
}
if (-not $BaseUrl.EndsWith('/')) { $BaseUrl += '/' }
$BasePath = ([uri]$BaseUrl).AbsolutePath
$RepoOwner = if ($RepoUrl -match '^https://[^/]+/(?<owner>[^/]+)/') { $Matches.owner } else { 'OWNER' }

#endregion

#region Validate packages

if (-not $SkipAnalyzer) {
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        throw 'PSScriptAnalyzer is required. Install it with: Install-PSResource PSScriptAnalyzer -Scope CurrentUser (or run with -SkipAnalyzer for a quick local check).'
    }
    Import-Module PSScriptAnalyzer -ErrorAction Stop
}

if (-not (Test-Path -LiteralPath $PackagesPath -PathType Container)) { throw "Packages folder not found: $PackagesPath" }

$mergeBase = $null
if ($BaseRef) {
    if (-not $HasGit) { throw '-BaseRef needs git on PATH.' }
    $result = Invoke-Git $PackagesPath @('merge-base', $BaseRef, 'HEAD')
    if ($result.ExitCode -ne 0) { throw "Can't find a merge base between '$BaseRef' and HEAD. In CI, check out with fetch-depth: 0." }
    $mergeBase = $result.Output[0]
}

$packages = [System.Collections.Generic.List[object]]::new()

foreach ($item in Get-ChildItem -LiteralPath $PackagesPath -Force | Sort-Object Name) {
    if (-not $item.PSIsContainer) {
        Add-Issue -File (Get-DisplayPath $item.FullName) -Rule 'StrayFile' -Message 'packages/ may only contain package folders.'
        continue
    }

    $id = $item.Name
    $pkgPath = $item.FullName
    $pkg = [pscustomobject]@{
        Id = $id; Path = $pkgPath; Manifest = $null; Files = @(); Scripts = [System.Collections.Generic.List[object]]::new()
        Widgets = [System.Collections.Generic.List[object]]::new(); Updated = $null; Size = 0
        RepoPath = [IO.Path]::GetRelativePath($RepoRoot, $item.FullName).Replace('\', '/')
    }
    $packages.Add($pkg)
    $display = Get-DisplayPath $pkgPath

    if ($id -cnotmatch '^[A-Z][A-Za-z0-9]*$' -or $id.Length -gt 50) {
        Add-Issue -Package $id -File $display -Rule 'InvalidPackageId' -Message "Folder name '$id' must be a PascalCase id: letters and digits, starting with a capital letter (for example CertificateTools)."
    }

    # Files: types, size, encoding.
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in Get-ChildItem -LiteralPath $pkgPath -Recurse -Force) {
        $relative = [IO.Path]::GetRelativePath($pkgPath, $entry.FullName).Replace('\', '/')
        $entryDisplay = Get-DisplayPath $entry.FullName
        if ($entry.LinkType) {
            Add-Issue -Package $id -File $entryDisplay -Rule 'SymlinkNotAllowed' -Message 'Symbolic links are not allowed in packages.'
            continue
        }
        if ($entry.PSIsContainer) { continue }
        $pkg.Size += $entry.Length
        if ($entry.Extension.ToLowerInvariant() -notin $Rules.AllowedExtensions) {
            Add-Issue -Package $id -File $entryDisplay -Rule 'FileTypeNotAllowed' -Message "Only $($Rules.AllowedExtensions -join ', ') files are allowed. Remove '$relative'."
            continue
        }
        $bytes = [IO.File]::ReadAllBytes($entry.FullName)
        if ([Array]::IndexOf($bytes, [byte]0) -ge 0) {
            Add-Issue -Package $id -File $entryDisplay -Rule 'BinaryFile' -Message 'Binary content is not allowed. Packages contain text files only.'
            continue
        }
        try { $null = $StrictUtf8.GetString($bytes) }
        catch {
            Add-Issue -Package $id -File $entryDisplay -Rule 'InvalidEncoding' -Message 'Save the file as UTF-8.'
            continue
        }
        $files.Add([pscustomobject]@{ Relative = $relative; FullName = $entry.FullName; Display = $entryDisplay; Size = $entry.Length })
    }
    $pkg.Files = @($files | Sort-Object { $_.Relative } -CaseSensitive)
    $maxBytes = $Rules.MaxPackageSizeKB * 1KB
    if ($pkg.Size -gt $maxBytes) {
        Add-Issue -Package $id -File $display -Rule 'PackageTooLarge' -Message ('Package is {0:N0} KB; the limit is {1} KB.' -f [math]::Ceiling($pkg.Size / 1KB), $Rules.MaxPackageSizeKB)
    }

    # module.psd1
    $manifestPath = Join-Path $pkgPath 'module.psd1'
    $manifestDisplay = Get-DisplayPath $manifestPath
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-Issue -Package $id -File $display -Rule 'ModuleManifestMissing' -Message 'module.psd1 is missing. Copy it from templates/package/.'
    }
    else {
        $data = Read-DataFile -Path $manifestPath
        switch ($data.Status) {
            'ParseError' { foreach ($e in $data.Errors) { Add-Issue -Package $id -File $manifestDisplay -Line $e.Extent.StartLineNumber -Rule 'ManifestParseError' -Message $e.Message } }
            'NotPlain' { Add-Issue -Package $id -File $manifestDisplay -Rule 'ManifestNotPlain' -Message $data.Message }
            'Ok' {
                $m = $data.Value
                # Line of each key, so errors point at the right line.
                $keyLine = @{}
                $lineNumber = 0
                foreach ($text in [IO.File]::ReadAllLines($manifestPath)) {
                    $lineNumber++
                    if ($text -match '^\s*([A-Za-z]+)\s*=' -and -not $keyLine.ContainsKey($Matches[1])) { $keyLine[$Matches[1]] = $lineNumber }
                }
                $missing = @($Rules.ManifestFields | Where-Object { -not $m.ContainsKey($_) })
                foreach ($field in $missing) { Add-Issue -Package $id -File $manifestDisplay -Line 1 -Rule 'ManifestFieldMissing' -Message "module.psd1 is missing the required field '$field'." }
                foreach ($key in $m.Keys) {
                    if ($key -notin $Rules.ManifestFields) { Add-Issue -Severity Warning -Package $id -File $manifestDisplay -Line $keyLine[$key] -Rule 'ManifestFieldUnknown' -Message "module.psd1 has an unknown field '$key'." }
                }
                $invalid = { param($field, $why) Add-Issue -Package $id -File $manifestDisplay -Line $keyLine[$field] -Rule 'ManifestFieldInvalid' -Message "$field $why" }
                if ($m.ContainsKey('Name') -and ($m.Name -isnot [string] -or -not (Test-SingleLine $m.Name 60))) { & $invalid 'Name' 'must be a single line of text, at most 60 characters.' }
                if ($m.ContainsKey('Description') -and ($m.Description -isnot [string] -or -not (Test-SingleLine $m.Description 200))) { & $invalid 'Description' 'must be one line of text, at most 200 characters.' }
                if ($m.ContainsKey('Author') -and ($m.Author -isnot [string] -or $m.Author -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$')) { & $invalid 'Author' "must be a GitHub username (found '$($m.Author)')." }
                if ($m.ContainsKey('Version') -and ($m.Version -isnot [string] -or $m.Version -notmatch $SemVerPattern)) {
                    Add-Issue -Package $id -File $manifestDisplay -Line $keyLine['Version'] -Rule 'InvalidVersion' -Message "Version '$($m.Version)' is not a semantic version. Use MAJOR.MINOR.PATCH, for example '1.0.0'."
                }
                if ($m.ContainsKey('MinOpsKitVersion') -and ($m.MinOpsKitVersion -isnot [string] -or $m.MinOpsKitVersion -notmatch $SemVerPattern)) {
                    Add-Issue -Package $id -File $manifestDisplay -Line $keyLine['MinOpsKitVersion'] -Rule 'InvalidVersion' -Message "MinOpsKitVersion '$($m.MinOpsKitVersion)' is not a semantic version, for example '0.1.0'."
                }
                if ($m.ContainsKey('Category') -and $m.Category -cnotin $Categories) {
                    Add-Issue -Package $id -File $manifestDisplay -Line $keyLine['Category'] -Rule 'InvalidCategory' -Message "Category '$($m.Category)' is not in build/categories.json. Use one of: $($Categories -join ', ')."
                }
                foreach ($field in 'Tags', 'RequiresModules') {
                    if ($m.ContainsKey($field) -and -not (Test-StringList $m[$field])) { & $invalid $field "must be an array of strings: @('a', 'b')." }
                }
                if ($m.ContainsKey('Tags') -and (Test-StringList $m.Tags)) {
                    $tags = Get-StringList $m.Tags
                    if ($tags.Count -gt 10) { & $invalid 'Tags' 'can have at most 10 entries.' }
                    foreach ($tag in $tags) { if ($tag -cnotmatch '^[a-z0-9][a-z0-9.+-]{0,29}$') { & $invalid 'Tags' "entry '$tag' must be lowercase letters, digits and dashes (max 30 characters)." } }
                }
                if ($m.ContainsKey('RequiresModules') -and (Test-StringList $m.RequiresModules)) {
                    foreach ($module in (Get-StringList $m.RequiresModules)) { if ($module -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { & $invalid 'RequiresModules' "entry '$module' is not a module name." } }
                }
                $pkg.Manifest = $m
            }
        }
    }

    # PowerShell files.
    foreach ($file in $pkg.Files) {
        $isPs1 = $file.Relative -like '*.ps1'
        $isPsd1 = $file.Relative -like '*.psd1'
        if (-not ($isPs1 -or $isPsd1)) { continue }

        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count) {
            foreach ($e in $errors) { Add-Issue -Package $id -File $file.Display -Line $e.Extent.StartLineNumber -Rule 'ParseError' -Message $e.Message }
            continue
        }
        Test-BannedPattern -Text $ast.Extent.Text -Tokens $tokens -Package $id -File $file.Display
        if (-not $isPs1) { continue }

        $name = [IO.Path]::GetFileNameWithoutExtension($file.Relative)
        $folder = [IO.Path]::GetDirectoryName($file.Relative)
        if ($name.StartsWith('_')) { continue }   # shared helper

        if ([string]::IsNullOrEmpty($folder)) {
            # Root script = menu entry.
            if ($name -cnotmatch '^(?<verb>[A-Z][a-z]+)-(?<noun>[A-Z][A-Za-z0-9]*)$' -or $Matches.verb -notin $ApprovedVerbs) {
                Add-Issue -Package $id -File $file.Display -Rule 'InvalidScriptName' -Message "Script '$($file.Relative)' must be named Verb-Noun.ps1 with an approved verb (Get-Verb), for example Get-ExpiringCertificate.ps1. Prefix helpers with _."
            }
            $info = Get-HashtableValue -Ast $ast -Name 'ScriptInfo'
            if ($info.Status -eq 'Missing') { Add-Issue -Package $id -File $file.Display -Rule 'ScriptInfoMissing' -Message 'Script has no top-level $ScriptInfo = @{ ... } hashtable.'; continue }
            if ($info.Status -eq 'NotPlain') { Add-Issue -Package $id -File $file.Display -Line $info.Line -Rule 'ScriptInfoNotPlain' -Message $info.Message; continue }
            $v = $info.Value
            Test-MetadataFields -Value $v -Kind 'ScriptInfo' -Required $Rules.ScriptInfoRequired -Optional $Rules.ScriptInfoOptional -Package $id -File $file.Display -Line $info.Line

            if ($name -match '^(Get|Test|Find)-') {
                $commands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique
                foreach ($command in $commands) {
                    if ($command -match '^(?<verb>\w+)-(?<noun>\S+)$' -and $Matches.verb -in $Rules.StateChangingVerbs -and $Matches.noun -notlike 'OpsKit*') {
                        Add-Issue -Severity Warning -Package $id -File $file.Display -Rule 'ReadOnlyScript' -Message "Get-, Test- and Find- scripts must be read-only, but this one calls $command."
                    }
                }
            }

            $modules = if (Test-StringList $v['RequiresModules']) { Get-StringList $v['RequiresModules'] } else { , [string[]]@() }
            $platforms = if (Test-StringList $v['Platforms']) { Get-StringList $v['Platforms'] } else { , [string[]]@() }
            $pkg.Scripts.Add([ordered]@{
                    id              = "$id/$name"
                    file            = $file.Relative
                    name            = [string]$v['Name']
                    description     = [string]$v['Description']
                    version         = [string]$v['Version']
                    requiresAdmin   = ($v['RequiresAdmin'] -eq $true)
                    requiresModules = [string[]]$modules
                    platforms       = [string[]]$platforms
                    parameters      = (Get-ScriptParameter -Ast $ast -Package $id -File $file.Display)
                })
        }
        elseif ($folder -eq 'Widgets') {
            if ($name -cnotmatch '^[A-Z][A-Za-z0-9]*$') {
                Add-Issue -Package $id -File $file.Display -Rule 'InvalidWidgetName' -Message "Widget '$($file.Relative)' must have a PascalCase name, for example Widgets/CertificateExpiry.ps1."
            }
            $info = Get-HashtableValue -Ast $ast -Name 'WidgetInfo'
            if ($info.Status -eq 'Missing') { Add-Issue -Package $id -File $file.Display -Rule 'WidgetInfoMissing' -Message 'Widget has no top-level $WidgetInfo = @{ ... } hashtable.'; continue }
            if ($info.Status -eq 'NotPlain') { Add-Issue -Package $id -File $file.Display -Line $info.Line -Rule 'WidgetInfoNotPlain' -Message $info.Message; continue }
            $v = $info.Value
            Test-MetadataFields -Value $v -Kind 'WidgetInfo' -Required $Rules.WidgetInfoRequired -Optional $Rules.WidgetInfoOptional -Package $id -File $file.Display -Line $info.Line
            $modules = if (Test-StringList $v['RequiresModules']) { Get-StringList $v['RequiresModules'] } else { , [string[]]@() }
            $platforms = if (Test-StringList $v['Platforms']) { Get-StringList $v['Platforms'] } else { , [string[]]@() }
            $pkg.Widgets.Add([ordered]@{
                    id              = "$id/$name"
                    file            = $file.Relative
                    name            = [string]$v['Name']
                    description     = [string]$v['Description']
                    requiresModules = [string[]]$modules
                    platforms       = [string[]]$platforms
                    refreshSeconds  = $(if ($v['RefreshSeconds'] -is [int]) { $v['RefreshSeconds'] } else { $null })
                })
        }
    }

    $parseFailures = @($Issues | Where-Object { $_.Package -eq $id -and $_.Rule -eq 'ParseError' } | ForEach-Object File)
    # PSScriptAnalyzer, skipping files that already failed to parse.
    $analyzerFindings = @()
    if (-not $SkipAnalyzer -and @($pkg.Files | Where-Object { $_.Relative -like '*.ps1' }).Count) {
        $analyzerFindings = @(Invoke-ScriptAnalyzer -Path $pkgPath -Recurse -ExcludeRule $Rules.AnalyzerExcludeRules -Severity Error, Warning)
    }
    foreach ($finding in $analyzerFindings) {
        $ignored = $Rules.AnalyzerIgnore | Where-Object { $finding.RuleName -eq $_.Rule -and $finding.Message -match $_.MessagePattern }
        $findingFile = Get-DisplayPath $finding.ScriptPath
        if ($ignored -or $findingFile -in $parseFailures) { continue }
        Add-Issue -Package $id -File $findingFile -Line ([int]$finding.Line) -Rule 'PSScriptAnalyzer' -Message "$($finding.RuleName): $($finding.Message)"
    }

    if ($pkg.Scripts.Count -eq 0 -and -not @($Issues | Where-Object { $_.Package -eq $id -and $_.Rule -in 'ScriptInfoMissing', 'ScriptInfoNotPlain', 'ParseError' })) {
        Add-Issue -Package $id -File $display -Rule 'NoScripts' -Message 'A package needs at least one Verb-Noun.ps1 script in its root folder.'
    }

    # Last commit date, and the version bump check.
    $pkg.Updated = [datetime]::UtcNow.ToString('yyyy-MM-dd')
    if ($HasGit) {
        $prefix = Invoke-Git $pkgPath @('rev-parse', '--show-prefix')
        if ($prefix.ExitCode -eq 0 -and $prefix.Output.Count -and $prefix.Output[0]) { $pkg.RepoPath = $prefix.Output[0].TrimEnd('/') }
        $log = Invoke-Git $pkgPath @('log', '-1', '--format=%cs', '--', '.')
        if ($log.ExitCode -eq 0 -and $log.Output.Count -and $log.Output[0] -match '^\d{4}-\d{2}-\d{2}$') { $pkg.Updated = $log.Output[0] }
    }

    if ($mergeBase -and $pkg.Manifest -and $pkg.Manifest.ContainsKey('Version') -and $pkg.Manifest.Version -match $SemVerPattern) {
        $changed = @(@((Invoke-Git $pkgPath @('diff', '--name-only', $mergeBase, '--', '.')).Output) +
            @((Invoke-Git $pkgPath @('ls-files', '--others', '--exclude-standard', '--', '.')).Output) | Where-Object { $_ })
        if ($changed.Count) {
            $prefix = (Invoke-Git $pkgPath @('rev-parse', '--show-prefix')).Output[0]
            $old = Invoke-Git $pkgPath @('show', "${mergeBase}:${prefix}module.psd1")
            if ($old.ExitCode -eq 0) {
                $oldData = Read-DataFile -Text ($old.Output -join "`n")
                if ($oldData.Status -eq 'Ok' -and $oldData.Value['Version'] -match $SemVerPattern -and
                    [semver]$pkg.Manifest.Version -le [semver]$oldData.Value['Version']) {
                    Add-Issue -Package $id -File $manifestDisplay -Line $keyLine['Version'] -Rule 'VersionNotBumped' `
                        -Message "Files changed compared with $BaseRef, but Version is $($pkg.Manifest.Version) (was $($oldData.Value['Version'])). Bump Version in module.psd1."
                }
            }
        }
    }
}

foreach ($group in $packages | Group-Object { $_.Id.ToLowerInvariant() } | Where-Object Count -gt 1) {
    foreach ($p in $group.Group) {
        Add-Issue -Package $p.Id -File (Get-DisplayPath $p.Path) -Rule 'DuplicatePackageId' -Message "Package id '$($p.Id)' clashes with $(($group.Group.Id | Where-Object { $_ -cne $p.Id }) -join ', ') (ids are case-insensitive)."
    }
}

#endregion

#region Build catalog

$catalogPackages = [System.Collections.Generic.List[object]]::new()
$zips = @{}
$generated = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

foreach ($pkg in $packages | Sort-Object Id) {
    if (@($Issues | Where-Object { $_.Package -eq $pkg.Id -and $_.Severity -eq 'Error' }).Count -or -not $pkg.Manifest) { continue }
    $m = $pkg.Manifest
    $zipName = "$($pkg.Id)-$($m.Version).zip"
    $zipBytes = New-ZipBytes -SourcePath $pkg.Path -RootName $pkg.Id -RelativePaths $pkg.Files.Relative -Timestamp ([datetime]$pkg.Updated)
    $zips[$zipName] = $zipBytes
    $srcBase = "${BaseUrl}src/$([uri]::EscapeDataString($pkg.Id))/"

    $entry = [ordered]@{
        id               = $pkg.Id
        name             = $m.Name
        description      = $m.Description
        version          = $m.Version
        author           = $m.Author
        category         = $m.Category
        tags             = Get-StringList $m.Tags
        requiresModules  = Get-StringList $m.RequiresModules
        minOpsKitVersion = $m.MinOpsKitVersion
        updated          = $pkg.Updated
        download         = [ordered]@{
            url    = "${BaseUrl}packages/$([uri]::EscapeDataString($zipName))"
            sha256 = Get-Sha256 $zipBytes
            size   = $zipBytes.Length
        }
        sourceUrl        = "$RepoUrl/tree/$Branch/$(ConvertTo-UrlPath $pkg.RepoPath)"
    }
    $readme = $pkg.Files | Where-Object { $_.Relative -ieq 'README.md' } | Select-Object -First 1
    if ($readme) { $entry.readmeUrl = $srcBase + (ConvertTo-UrlPath $readme.Relative) }
    $entry.files = [object[]]@(foreach ($f in $pkg.Files) { [ordered]@{ path = $f.Relative; url = $srcBase + (ConvertTo-UrlPath $f.Relative); size = $f.Size } })
    $entry.scripts = [object[]]@($pkg.Scripts | Sort-Object { $_.id })
    $entry.widgets = [object[]]@($pkg.Widgets | Sort-Object { $_.id })
    $catalogPackages.Add($entry)
}

$catalog = [ordered]@{
    schemaVersion = 1
    generated     = $generated
    catalogUrl    = $BaseUrl
    categories    = [string[]]$Categories
    packages      = $catalogPackages
}
$catalogJson = $catalog | ConvertTo-Json -Depth 20

$schemaText = Get-Content -LiteralPath (Join-Path $RepoRoot 'schema' 'catalog.schema.json') -Raw
$schemaErrors = $null
if (-not (Test-Json -Json $catalogJson -Schema $schemaText -ErrorVariable schemaErrors -ErrorAction SilentlyContinue)) {
    foreach ($e in $schemaErrors) { Add-Issue -File 'catalog.json' -Rule 'SchemaInvalid' -Message "catalog.json does not match schema/catalog.schema.json: $($e.Exception.Message) $($e.ErrorDetails.Message)" }
}

#endregion

#region Report

$errorList = @($Issues | Where-Object Severity -eq 'Error')
$warningList = @($Issues | Where-Object Severity -eq 'Warning')
$failedPackages = @($packages | Where-Object { $id = $_.Id; @($errorList | Where-Object Package -eq $id).Count })

Write-Host ''
foreach ($pkg in $packages) {
    $pkgErrors = @($errorList | Where-Object Package -eq $pkg.Id)
    $pkgWarnings = @($warningList | Where-Object Package -eq $pkg.Id)
    $version = if ($pkg.Manifest -and $pkg.Manifest.ContainsKey('Version')) { $pkg.Manifest.Version } else { '?' }
    $counts = "$($pkg.Scripts.Count) script(s), $($pkg.Widgets.Count) widget(s)"
    if ($pkgErrors.Count) { Write-Host "  ✘ $($pkg.Id) $version  ($counts)" -ForegroundColor Red }
    else { Write-Host "  ✔ $($pkg.Id) $version  ($counts)" -ForegroundColor Green }
    foreach ($i in $pkgErrors + $pkgWarnings) {
        $where = if ($i.Line) { "$($i.File):$($i.Line)" } else { $i.File }
        $color = if ($i.Severity -eq 'Error') { 'Red' } else { 'Yellow' }
        Write-Host "      $($i.Severity.ToUpper()) [$($i.Rule)] $where" -ForegroundColor $color
        Write-Host "        $($i.Message)"
    }
}
foreach ($i in @($Issues | Where-Object { -not $_.Package })) {
    Write-Host "  $($i.Severity.ToUpper()) [$($i.Rule)] $($i.File): $($i.Message)" -ForegroundColor $(if ($i.Severity -eq 'Error') { 'Red' } else { 'Yellow' })
}
Write-Host ''
Write-Host ("{0} package(s): {1} passed, {2} failed. {3} error(s), {4} warning(s)." -f $packages.Count, ($packages.Count - $failedPackages.Count), $failedPackages.Count, $errorList.Count, $warningList.Count) `
    -ForegroundColor $(if ($errorList.Count) { 'Red' } else { 'Green' })

if ($env:GITHUB_ACTIONS -eq 'true') {
    foreach ($i in $Issues) {
        $props = @()
        if ($i.File -and $i.File -ne 'catalog.json') { $props += "file=$(ConvertTo-AnnotationText $i.File -Property)" }
        if ($i.Line) { $props += "line=$($i.Line)" }
        $props += "title=$(ConvertTo-AnnotationText $i.Rule -Property)"
        Write-Host "::$($i.Severity.ToLower()) $($props -join ',')::$(ConvertTo-AnnotationText $i.Message)"
    }
}

if ($SummaryPath) {
    $md = [System.Text.StringBuilder]::new()
    $status = if ($errorList.Count) { '❌ Validation failed' } else { '✅ Validation passed' }
    $null = $md.AppendLine("## OpsKit Catalog: $status").AppendLine()
    $null = $md.AppendLine("$($packages.Count) package(s): **$($packages.Count - $failedPackages.Count) passed**, **$($failedPackages.Count) failed**. $($errorList.Count) error(s), $($warningList.Count) warning(s).").AppendLine()
    $null = $md.AppendLine('| Check | Result |').AppendLine('| --- | --- |')
    foreach ($check in $AllChecks) {
        $checkErrors = @($errorList | Where-Object { $CheckOf[$_.Rule] -eq $check }).Count
        $skipped = ($check -eq 'PSScriptAnalyzer' -and $SkipAnalyzer) -or ($check -like 'Version bumped*' -and -not $BaseRef)
        $result = if ($skipped) { '⏭️ skipped' } elseif ($checkErrors) { "❌ $checkErrors error(s)" } else { '✅ passed' }
        $null = $md.AppendLine("| $check | $result |")
    }
    $null = $md.AppendLine().AppendLine('| Package | Version | Scripts | Widgets | Result |').AppendLine('| --- | --- | --- | --- | --- |')
    foreach ($pkg in $packages) {
        $n = @($errorList | Where-Object Package -eq $pkg.Id).Count
        $version = if ($pkg.Manifest -and $pkg.Manifest.ContainsKey('Version')) { $pkg.Manifest.Version } else { '?' }
        $null = $md.AppendLine("| ``$($pkg.Id)`` | $version | $($pkg.Scripts.Count) | $($pkg.Widgets.Count) | $(if ($n) { "❌ $n error(s)" } else { '✅' }) |")
    }
    foreach ($section in @(@{ Title = 'Errors'; Items = $errorList }, @{ Title = 'Warnings'; Items = $warningList })) {
        if (-not $section.Items.Count) { continue }
        $null = $md.AppendLine().AppendLine("### $($section.Title)").AppendLine()
        foreach ($i in $section.Items) {
            $where = if ($i.Line) { "$($i.File):$($i.Line)" } else { $i.File }
            $null = $md.AppendLine("- ``$where`` **$($i.Rule)**: $($i.Message -replace '\|', '\|')")
        }
    }
    if ($Overrides.Count) {
        $null = $md.AppendLine().AppendLine('### Overrides that need maintainer approval').AppendLine()
        foreach ($o in $Overrides) { $null = $md.AppendLine("- ``$($o.File):$($o.Line)`` allows **$($o.Rules -join ', ')**: $($o.Reason)") }
        $null = $md.AppendLine().AppendLine('A maintainer approves these by adding the `override-approved` label.')
    }
    Add-Content -LiteralPath $SummaryPath -Value $md.ToString() -Encoding utf8NoBOM
}

#endregion

#region Write site

$wroteSite = $false
if (-not $ValidateOnly -and -not $errorList.Count) {
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    $marker = Join-Path $OutputPath '.opskit-catalog-build'
    if (Test-Path -LiteralPath $OutputPath) {
        if (@(Get-ChildItem -LiteralPath $OutputPath -Force).Count -and -not (Test-Path -LiteralPath $marker)) {
            throw "OutputPath '$OutputPath' is not empty and was not created by this script. Choose an empty or new folder."
        }
        Remove-Item -LiteralPath $OutputPath -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $OutputPath
    Set-Content -LiteralPath $marker -Value 'Created by build/Build-Catalog.ps1. This folder is deleted on every build.'

    # Pages from site-src, with placeholders filled in.
    $siteSrc = Join-Path $RepoRoot 'site-src'
    $tokens = [ordered]@{
        '{{BASE_URL}}'   = $BaseUrl
        '{{BASE_PATH}}'  = $BasePath
        '{{REPO_URL}}'   = $RepoUrl
        '{{OPSKIT_URL}}' = "https://github.com/$RepoOwner/OpsKit"
        '{{IDEAS_URL}}'  = "$RepoUrl/blob/$Branch/IDEAS.md"
        '{{BRANCH}}'     = $Branch
        '{{YEAR}}'       = [string](Get-Date).Year
    }
    # Shared header and footer. A page writes {{HEADER:browse}} to mark Browse as the current nav item,
    # or {{HEADER}} for none, and {{FOOTER}}. Partials are not copied to the output.
    $partials = @{}
    foreach ($p in Get-ChildItem -LiteralPath (Join-Path $siteSrc '_partials') -Filter *.html -File) {
        $partials[$p.BaseName] = [IO.File]::ReadAllText($p.FullName).TrimEnd()
    }
    $headerFor = {
        param($match)
        $page = $match.Groups[1].Value
        $html = $partials['header']
        foreach ($nav in 'BROWSE', 'CONTRIBUTE', 'ABOUT') {
            $html = $html.Replace("{{NAV_$nav}}", $(if ($page -eq $nav) { ' aria-current="page"' } else { '' }))
        }
        $html
    }
    foreach ($file in Get-ChildItem -LiteralPath $siteSrc -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($siteSrc, $file.FullName)
        if ($relative -like '_partials*') { continue }
        $target = Join-Path $OutputPath $relative
        $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
        if ($file.Extension -in '.html', '.txt', '.xml', '.webmanifest') {
            $text = [IO.File]::ReadAllText($file.FullName)
            $text = [regex]::Replace($text, '\{\{HEADER(?::([a-z]+))?\}\}', [Text.RegularExpressions.MatchEvaluator]$headerFor)
            $text = $text.Replace('{{FOOTER}}', $partials['footer'])
            foreach ($key in $tokens.Keys) { $text = $text.Replace($key, $tokens[$key]) }
            [IO.File]::WriteAllText($target, $text, $Utf8NoBom)
        }
        else { Copy-Item -LiteralPath $file.FullName -Destination $target }
    }

    # Logo list for the package tiles: assets/logos/<PackageId>.svg|png|webp -> { "<PackageId>": "<path>" }.
    # File names match package ids case-insensitively (Pages URLs are case-sensitive, so the real name is kept).
    $logoDir = Join-Path $siteSrc 'assets' 'logos'
    $logos = [ordered]@{}
    if (Test-Path -LiteralPath $logoDir) {
        foreach ($logo in Get-ChildItem -LiteralPath $logoDir -File | Sort-Object Name) {
            if ($logo.Name -notmatch '^([A-Za-z][A-Za-z0-9]*)\.(svg|png|webp)$') { continue }
            $id = @($packages.Id) | Where-Object { $_ -eq $Matches[1] } | Select-Object -First 1
            if ($id -and -not $logos.Contains($id)) { $logos[$id] = "assets/logos/$($logo.Name)" }
        }
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $OutputPath 'assets' 'logos') -Force
    [IO.File]::WriteAllText((Join-Path $OutputPath 'assets' 'logos' 'index.json'), ($logos | ConvertTo-Json -Compress), $Utf8NoBom)

    [IO.File]::WriteAllText((Join-Path $OutputPath 'catalog.json'), $catalogJson, $Utf8NoBom)

    $zipDir = New-Item -ItemType Directory -Path (Join-Path $OutputPath 'packages') -Force
    foreach ($name in $zips.Keys) { [IO.File]::WriteAllBytes((Join-Path $zipDir $name), $zips[$name]) }

    foreach ($pkg in $packages) {
        foreach ($f in $pkg.Files) {
            $target = Join-Path $OutputPath 'src' $pkg.Id $f.Relative
            $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
            Copy-Item -LiteralPath $f.FullName -Destination $target
        }
    }

    $templatePath = Join-Path $RepoRoot 'templates' 'package'
    if (Test-Path -LiteralPath $templatePath) {
        $templateFiles = @(Get-ChildItem -LiteralPath $templatePath -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($templatePath, $_.FullName).Replace('\', '/') })
        $downloads = New-Item -ItemType Directory -Path (Join-Path $OutputPath 'downloads') -Force
        $templateZip = New-ZipBytes -SourcePath $templatePath -RootName 'MyPackage' -RelativePaths $templateFiles -Timestamp ([datetime]'2026-01-01')
        [IO.File]::WriteAllBytes((Join-Path $downloads 'opskit-package-template.zip'), $templateZip)
    }

    $wroteSite = $true
    Write-Host "Site written to $OutputPath ($($catalogPackages.Count) package(s), base URL $BaseUrl)" -ForegroundColor Cyan
}

#endregion

if ($PassThru) {
    [pscustomobject]@{
        Success     = ($errorList.Count -eq 0)
        Errors      = $errorList
        Warnings    = $warningList
        Overrides   = @($Overrides)
        Packages    = @($packages.Id)
        Catalog     = $catalog
        CatalogJson = $catalogJson
        OutputPath  = $(if ($wroteSite) { $OutputPath })
    }
}

if ($errorList.Count) { exit 1 }
