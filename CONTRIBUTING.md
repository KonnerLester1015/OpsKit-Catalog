# Contributing to the OpsKit Catalog

Thanks for sharing your scripts. Everything here is free and MIT licensed, and every package is reviewed by a
maintainer before it goes live.

## Adding a package

1. **Pick an id.** PascalCase letters and digits, unique in the catalog, for example `CertificateTools`.
   The folder name is the id.
2. **Start from the template.** Copy [`templates/package/`](templates/package/) to `packages/<Id>/`.
3. **Fill in `module.psd1`.** Every field is required:

   ```powershell
   @{
       Name             = 'Certificate Tools'
       Description      = 'Find expiring certificates on local and remote machines.'   # one line
       Version          = '1.0.0'                # semver
       Author           = 'your-github-username'
       Category         = 'Security'             # see build/categories.json
       Tags             = @('certificates', 'pki')
       RequiresModules  = @()                    # modules every script in the package needs
       MinOpsKitVersion = '0.1.0'
   }
   ```

4. **Write your scripts.** Each `Verb-Noun.ps1` in the package root is one menu entry. Files starting with
   `_` are shared helpers. Widgets go in `Widgets/`. An optional `README.md` is shown on the package page.
5. **Test in OpsKit**, then run the checks locally (below).
6. **Open a pull request** and fill in the checklist. One package per pull request.

## Script rules

- A top-level `$ScriptInfo = @{ ... }` with plain values only (no variables, commands or expressions):
  `Name`, `Description`, `Version`, `Author` are required; `Tags`, `RequiresModules`, `RequiresAdmin` and
  `Platforms` (`Windows`, `Linux`, `macOS`; empty means all) are optional.
- A normal `param()` block. OpsKit prompts for mandatory parameters, using `HelpMessage` as the prompt and
  `ValidateSet` as a pick list. Give every mandatory parameter a `HelpMessage`.
- Return objects. OpsKit shows them as a table and offers CSV and JSON export.
- Use the OpsKit helpers instead of `Write-Host`, `Read-Host` or `Format-Table`: `Read-OpsKitText`,
  `Read-OpsKitList`, `Read-OpsKitChoice`, `Read-OpsKitConfirm`, `Write-OpsKitStatus`, `Write-OpsKitSection`,
  `Show-OpsKitTable`, `Show-OpsKitDetails`, `Invoke-OpsKitTask`, `Invoke-OpsKitForEach`,
  `Export-OpsKitResult`, `Write-OpsKitLog`, `Assert-OpsKitModule`, `Test-OpsKitAdmin`, `Get-OpsKitConfig`,
  `Set-OpsKitModuleSetting`.
- `Get-`, `Test-` and `Find-` scripts must be read-only. Anything that changes something must confirm first.
- No hard-coded secrets, and nothing specific to your environment (tenant ids, server names, paths).

Widgets have a top-level `$WidgetInfo = @{ Name; Description; RequiresModules; Platforms; RefreshSeconds }` and
return an `[ordered]` hashtable of label/value rows. They must be fast and read-only: no prompts, no sign-ins.

## Running the checks locally

```powershell
Install-PSResource PSScriptAnalyzer -Scope CurrentUser
./build/Build-Catalog.ps1 -ValidateOnly
./build/Build-Catalog.ps1 -ValidateOnly -BaseRef origin/main   # also checks the version bump
```

The output lists each package with any errors and warnings, with file and line. CI runs exactly this, and
adds a summary to the pull request's checks.

## Updating a package

Change the files and bump `Version` in `module.psd1` in the same pull request. CI fails if files changed but
the version didn't. Use semver: patch for fixes, minor for new scripts or parameters, major when existing
scripts behave differently.

## Banned patterns and overrides

[`build/rules.psd1`](build/rules.psd1) lists patterns that fail the build, because they are how malicious scripts
usually hide or persist. Mentioning them in comments is fine; only code is checked. If one is a false alarm,
allow that line with a comment on the same line or the line above:

```powershell
# opskit-allow DownloadCode: downloads the vendor's signed CSV feed, never executes it
```

The reason is required. CI keeps failing until a maintainer reviews the override and adds the
`override-approved` label.

## Changes to the catalog itself

Changes to `build/`, `schema/`, `site-src/` or the workflows are welcome too. Run `Invoke-Pester ./tests`
before opening the pull request, and add a fixture under `tests/fixtures/` for any new rule. Pull requests are
validated with the rules from `main`, so rule changes need to be merged before packages that depend on them.

Changes to `catalog.json` must stay backwards compatible within `schemaVersion: 1` (new optional fields only),
because OpsKit reads it.

## Maintainer review

Maintainers read every line of a new package or a change. Things we look for beyond what CI checks: does the
script do what its name and description say, do changes confirm first, does it handle errors per item, and
would we be comfortable running it in production.
