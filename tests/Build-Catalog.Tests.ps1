#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
    $BuildScript = Join-Path $RepoRoot 'build' 'Build-Catalog.ps1'
    $Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $SchemaText = Get-Content (Join-Path $RepoRoot 'schema' 'catalog.schema.json') -Raw

    # Fixture runs must not write to the real job summary or post annotations to the PR.
    $script:SavedEnv = @{ GITHUB_ACTIONS = $env:GITHUB_ACTIONS; GITHUB_STEP_SUMMARY = $env:GITHUB_STEP_SUMMARY }
    $env:GITHUB_ACTIONS = $null
    $env:GITHUB_STEP_SUMMARY = $null

    function Invoke-Build {
        param([string] $PackagesPath, [switch] $SkipAnalyzer, [hashtable] $Extra = @{})
        $params = @{ PackagesPath = $PackagesPath; ValidateOnly = $true; PassThru = $true; SummaryPath = ''; SkipAnalyzer = $SkipAnalyzer } + $Extra
        & $BuildScript @params 6>$null
    }

    function Copy-Fixture([string] $Path, [string] $Name = 'Fixture') {
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString('n')) 'packages'
        $null = New-Item -ItemType Directory -Path $target -Force
        Copy-Item -LiteralPath $Path -Destination (Join-Path $target $Name) -Recurse
        $target
    }
}

AfterAll {
    $env:GITHUB_ACTIONS = $script:SavedEnv.GITHUB_ACTIONS
    $env:GITHUB_STEP_SUMMARY = $script:SavedEnv.GITHUB_STEP_SUMMARY
}

# Checks the real packages/ folder. CI covers this in its own step, so the Pester step there excludes this tag.
Describe 'Seed packages' -Tag 'Packages' {
    It 'all pass validation, including PSScriptAnalyzer' {
        $result = Invoke-Build -PackagesPath (Join-Path $RepoRoot 'packages')
        $result.Errors | ForEach-Object { "$($_.File):$($_.Line) [$($_.Rule)] $($_.Message)" } | Should -BeNullOrEmpty
        $result.Success | Should -BeTrue
        $result.Packages.Count | Should -Be @(Get-ChildItem (Join-Path $RepoRoot 'packages') -Directory).Count
    }
}

Describe 'Bad packages are rejected' {
    It '<Case> fails with <Rule>' -ForEach @(
        @{ Case = 'MissingManifest'; Rule = 'ModuleManifestMissing' }
        @{ Case = 'MissingField'; Rule = 'ManifestFieldMissing' }
        @{ Case = 'BadCategory'; Rule = 'InvalidCategory' }
        @{ Case = 'BadVersion'; Rule = 'InvalidVersion' }
        @{ Case = 'BadPackageId'; Rule = 'InvalidPackageId' }
        @{ Case = 'ManifestNotPlain'; Rule = 'ManifestNotPlain' }
        @{ Case = 'ParseError'; Rule = 'ParseError' }
        @{ Case = 'NoScriptInfo'; Rule = 'ScriptInfoMissing' }
        @{ Case = 'ScriptInfoExpression'; Rule = 'ScriptInfoNotPlain' }
        @{ Case = 'ScriptInfoFieldMissing'; Rule = 'ScriptInfoFieldMissing' }
        @{ Case = 'BadPlatform'; Rule = 'ScriptInfoFieldInvalid' }
        @{ Case = 'WidgetNoInfo'; Rule = 'WidgetInfoMissing' }
        @{ Case = 'BadScriptName'; Rule = 'InvalidScriptName' }
        @{ Case = 'NoScripts'; Rule = 'NoScripts' }
        @{ Case = 'InvokeExpression'; Rule = 'InvokeExpression' }
        @{ Case = 'DownloadCode'; Rule = 'DownloadCode' }
        @{ Case = 'DynamicCode'; Rule = 'DynamicCode' }
        @{ Case = 'EncodedCommand'; Rule = 'EncodedCommand' }
        @{ Case = 'Base64Payload'; Rule = 'Base64Payload' }
        @{ Case = 'DisableSecurity'; Rule = 'DisableSecurity' }
        @{ Case = 'HardcodedSecret'; Rule = 'HardcodedSecret' }
        @{ Case = 'PlainTextSecureString'; Rule = 'HardcodedSecret' }
        @{ Case = 'PersistenceLocation'; Rule = 'PersistenceLocation' }
        @{ Case = 'ExecutionPolicy'; Rule = 'ExecutionPolicy' }
        @{ Case = 'HostOutput'; Rule = 'HostOutput' }
        @{ Case = 'FileTypeNotAllowed'; Rule = 'FileTypeNotAllowed' }
        @{ Case = 'AnalyzerWarning'; Rule = 'PSScriptAnalyzer' }
        @{ Case = 'OverrideMissingReason'; Rule = 'OverrideMissingReason' }
    ) {
        $result = Invoke-Build -PackagesPath (Join-Path $Fixtures 'bad' $Case)
        $result.Success | Should -BeFalse
        $result.Errors.Rule | Should -Contain $Rule
        $LASTEXITCODE | Should -Be 1
    }

    It 'points module.psd1 errors at the right line' {
        $result = Invoke-Build -PackagesPath (Join-Path $Fixtures 'bad' 'BadCategory') -SkipAnalyzer
        ($result.Errors | Where-Object Rule -eq 'InvalidCategory').Line | Should -Be 6
    }

    It 'rejects files with binary content' {
        $packages = Copy-Fixture (Join-Path $Fixtures 'good' 'GoodPackage') 'GoodPackage'
        [IO.File]::WriteAllBytes((Join-Path $packages 'GoodPackage' 'Notes.md'), [byte[]](0x4D, 0x5A, 0x00, 0x01))
        $result = Invoke-Build -PackagesPath $packages -SkipAnalyzer
        $result.Errors.Rule | Should -Contain 'BinaryFile'
    }

    It 'rejects packages over the size limit' {
        $packages = Copy-Fixture (Join-Path $Fixtures 'good' 'GoodPackage') 'GoodPackage'
        $limit = (Import-PowerShellDataFile (Join-Path $RepoRoot 'build' 'rules.psd1')).MaxPackageSizeKB
        Set-Content -LiteralPath (Join-Path $packages 'GoodPackage' 'Big.md') -Value ('x' * (($limit + 1) * 1KB))
        $result = Invoke-Build -PackagesPath $packages -SkipAnalyzer
        $result.Errors.Rule | Should -Contain 'PackageTooLarge'
    }

    It 'rejects ids that differ only by case' -Skip:(-not $IsLinux) {
        $packages = Copy-Fixture (Join-Path $Fixtures 'good' 'GoodPackage') 'GoodPackage'
        Copy-Item -LiteralPath (Join-Path $packages 'GoodPackage') -Destination (Join-Path $packages 'Goodpackage') -Recurse
        $result = Invoke-Build -PackagesPath $packages -SkipAnalyzer
        $result.Errors.Rule | Should -Contain 'DuplicatePackageId'
    }
}

Describe 'Banned pattern overrides' {
    BeforeAll { $overridePath = Join-Path $Fixtures 'override' 'Override' }

    It 'passes with a warning when overrides are not enforced' {
        $result = Invoke-Build -PackagesPath $overridePath -SkipAnalyzer
        $result.Success | Should -BeTrue
        $result.Warnings.Rule | Should -Contain 'OverrideNeedsApproval'
        $result.Overrides.Count | Should -Be 1
        $result.Overrides[0].Reason | Should -Be 'fixture for the override approval test'
    }

    It 'fails when maintainer approval is required' {
        $result = Invoke-Build -PackagesPath $overridePath -SkipAnalyzer -Extra @{ RequireOverrideApproval = $true }
        $result.Success | Should -BeFalse
        $result.Errors.Rule | Should -Contain 'OverrideNeedsApproval'
    }

    It 'ignores banned commands that only appear in comments' {
        $result = Invoke-Build -PackagesPath (Join-Path $Fixtures 'good') -SkipAnalyzer
        $result.Errors | Should -BeNullOrEmpty
    }
}

Describe 'Version bump check' -Skip:(-not (Get-Command git -ErrorAction Ignore)) {
    BeforeAll {
        $repo = Join-Path $TestDrive 'bump-repo'
        $null = New-Item -ItemType Directory -Path (Join-Path $repo 'packages') -Force
        Copy-Item -LiteralPath (Join-Path $Fixtures 'good' 'GoodPackage') -Destination (Join-Path $repo 'packages' 'GoodPackage') -Recurse
        function Invoke-TestGit { & git -C $repo @args 2>&1 | Out-Null; if ($LASTEXITCODE) { throw "git $args failed" } }
        Invoke-TestGit init --quiet --initial-branch=main
        Invoke-TestGit config user.name 'Test'
        Invoke-TestGit config user.email 'test@example.invalid'
        Invoke-TestGit config commit.gpgsign false
        Invoke-TestGit add -A
        Invoke-TestGit commit --quiet -m 'Add package'
        Invoke-TestGit checkout --quiet -b change
        Add-Content -LiteralPath (Join-Path $repo 'packages' 'GoodPackage' 'README.md') -Value 'A change.'
        $manifest = Join-Path $repo 'packages' 'GoodPackage' 'module.psd1'
    }

    It 'fails when files changed but the version did not' {
        $result = Invoke-Build -PackagesPath (Join-Path $repo 'packages') -SkipAnalyzer -Extra @{ BaseRef = 'main' }
        $result.Errors.Rule | Should -Contain 'VersionNotBumped'
    }

    It 'passes once the version is bumped' {
        (Get-Content $manifest -Raw).Replace("'1.2.3'", "'1.2.4'") | Set-Content -LiteralPath $manifest -NoNewline
        $result = Invoke-Build -PackagesPath (Join-Path $repo 'packages') -SkipAnalyzer -Extra @{ BaseRef = 'main' }
        $result.Errors | Should -BeNullOrEmpty
    }
}

Describe 'Package template' {
    It 'passes validation once Script.ps1 is renamed' {
        $packages = Copy-Fixture (Join-Path $RepoRoot 'templates' 'package') 'MyPackage'
        Rename-Item -LiteralPath (Join-Path $packages 'MyPackage' 'Script.ps1') -NewName 'Get-LowDiskSpace.ps1'
        $result = Invoke-Build -PackagesPath $packages
        $result.Errors | ForEach-Object { "$($_.File):$($_.Line) [$($_.Rule)] $($_.Message)" } | Should -BeNullOrEmpty
    }
}

Describe 'Site build' {
    BeforeAll {
        $baseUrl = 'https://example.test/catalog/'
        $site = Join-Path $TestDrive 'site'
        # Fixtures only, so this test doesn't depend on the state of packages/.
        $packages = Join-Path $TestDrive 'site-packages'
        $null = New-Item -ItemType Directory -Path $packages
        Copy-Item -LiteralPath (Join-Path $Fixtures 'good' 'GoodPackage') -Destination (Join-Path $packages 'GoodPackage') -Recurse
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'templates' 'package') -Destination (Join-Path $packages 'MyPackage') -Recurse
        Rename-Item -LiteralPath (Join-Path $packages 'MyPackage' 'Script.ps1') -NewName 'Get-LowDiskSpace.ps1'
        $result = & $BuildScript -PackagesPath $packages -OutputPath $site -BaseUrl $baseUrl -RepoUrl 'https://github.com/octocat/opskit-catalog' -SummaryPath '' -SkipAnalyzer -PassThru 6>$null
        $catalogText = Get-Content (Join-Path $site 'catalog.json') -Raw
        $catalog = $catalogText | ConvertFrom-Json
        $good = $catalog.packages | Where-Object id -eq 'GoodPackage'
    }

    It 'writes catalog.json that matches the schema' {
        $result.Success | Should -BeTrue
        Test-Json -Json $catalogText -Schema $SchemaText | Should -BeTrue
        $catalog.schemaVersion | Should -Be 1
        $catalog.catalogUrl | Should -Be $baseUrl
        $catalog.packages.Count | Should -Be @(Get-ChildItem $packages -Directory).Count
    }

    It 'uses absolute URLs built from the base URL' {
        foreach ($p in $catalog.packages) {
            $p.download.url | Should -BeLike "${baseUrl}packages/*"
            $p.sourceUrl | Should -BeLike 'https://github.com/octocat/opskit-catalog/tree/main/*'
            foreach ($f in $p.files) { $f.url | Should -BeLike "${baseUrl}src/$($p.id)/*" }
        }
    }

    It 'writes zips whose sha256 and size match catalog.json' {
        foreach ($p in $catalog.packages) {
            $zip = Join-Path $site 'packages' "$($p.id)-$($p.version).zip"
            $zip | Should -Exist
            (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $p.download.sha256
            (Get-Item $zip).Length | Should -Be $p.download.size
        }
    }

    It 'puts the package folder at the root of the zip' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $site 'packages' 'GoodPackage-1.2.3.zip'))
        try { $entries = @($zip.Entries.FullName) } finally { $zip.Dispose() }
        $entries | Should -Contain 'GoodPackage/module.psd1'
        $entries | Should -Contain 'GoodPackage/Widgets/ServiceSummary.ps1'
        $entries | Where-Object { $_ -notlike 'GoodPackage/*' } | Should -BeNullOrEmpty
    }

    It 'builds identical zips on every run' {
        $again = & $BuildScript -PackagesPath $packages -BaseUrl $baseUrl -SummaryPath '' -SkipAnalyzer -ValidateOnly -PassThru 6>$null
        ($again.Catalog.packages | ForEach-Object { $_.download.sha256 }) | Should -Be ($catalog.packages.download.sha256)
    }

    It 'copies raw sources to src/<id>/' {
        foreach ($f in $good.files) { Join-Path $site 'src' 'GoodPackage' $f.path | Should -Exist }
        $good.readmeUrl | Should -Be "${baseUrl}src/GoodPackage/README.md"
    }

    It 'reads script and parameter metadata without running the script' {
        $script = $good.scripts | Where-Object id -eq 'GoodPackage/Get-ServiceState'
        $script.name | Should -Be 'Service State'
        $script.requiresAdmin | Should -BeTrue
        $script.platforms | Should -Be @('Windows')
        $script.parameters.name | Should -Be @('Name', 'State', 'ComputerName', 'IncludeDisabled')
        ($script.parameters | Where-Object name -eq 'State').validateSet | Should -Be @('Running', 'Stopped')
        ($script.parameters | Where-Object name -eq 'Name').helpMessage | Should -Be 'Service name'
        ($script.parameters | Where-Object name -eq 'ComputerName').type | Should -Be 'string[]'
        ($script.parameters | Where-Object name -eq 'IncludeDisabled').mandatory | Should -BeFalse
        $good.scripts.Count | Should -Be 1   # _Helpers.ps1 is not a menu entry
        $good.widgets[0].id | Should -Be 'GoodPackage/ServiceSummary'
        $good.widgets[0].refreshSeconds | Should -Be 60
    }

    It 'fills in the placeholders in the pages' {
        foreach ($page in Get-ChildItem $site -Filter *.html) {
            Get-Content $page.FullName -Raw | Should -Not -Match '\{\{[A-Z_]+(:[a-z]+)?\}\}'
        }
        Join-Path $site '_partials' | Should -Not -Exist
        Get-Content (Join-Path $site 'browse.html') -Raw | Should -Match '<a href="browse.html" aria-current="page">Browse</a>'
        Get-Content (Join-Path $site 'index.html') -Raw | Should -Not -Match 'aria-current'
        Join-Path $site 'downloads' 'opskit-package-template.zip' | Should -Exist
    }

    It 'refuses to overwrite a folder it did not create' {
        $other = Join-Path $TestDrive 'not-a-site'
        $null = New-Item -ItemType Directory -Path $other
        Set-Content -LiteralPath (Join-Path $other 'keep.txt') -Value 'important'
        { & $BuildScript -PackagesPath $packages -OutputPath $other -SummaryPath '' -SkipAnalyzer 6>$null } | Should -Throw '*not empty*'
        Join-Path $other 'keep.txt' | Should -Exist
    }
}

Describe 'catalog.schema.json' {
    It 'rejects a package without a download' {
        $catalog = [ordered]@{
            schemaVersion = 1; generated = '2026-11-07T12:00:00Z'; catalogUrl = 'https://example.test/'
            packages      = @([ordered]@{
                    id = 'Broken'; name = 'Broken'; description = 'x'; version = '1.0.0'; author = 'octocat'; category = 'Other'
                    tags = @(); requiresModules = @(); minOpsKitVersion = '0.1.0'; updated = '2026-11-07'
                    sourceUrl = 'https://github.com/octocat/x'; files = @(); scripts = @(); widgets = @()
                })
        }
        Test-Json -Json ($catalog | ConvertTo-Json -Depth 10) -Schema $SchemaText -ErrorAction SilentlyContinue | Should -BeFalse
    }
}
