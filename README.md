# OpsKit Catalog

Free, community-made PowerShell script packages for [OpsKit](https://github.com/KonnerLester1015/OpsKit), the
PowerShell 7.4+ terminal toolkit for system administrators.

- **Website:** <https://konnerlester1015.github.io/OpsKit-Catalog/>
- **Machine-readable catalog:** <https://konnerlester1015.github.io/OpsKit-Catalog/catalog.json>

Every package is MIT licensed. The site is static files on GitHub Pages: no accounts, ratings, comments,
backend, analytics, tracking or cookies.

## What's in here

A package is one folder under [`packages/`](packages/) and becomes one OpsKit menu entry. CI validates
every package on each pull request. On every push to `main`, the same build script writes `catalog.json`,
one zip per package and the website, and deploys them to GitHub Pages.

```
packages/                    community packages
build/
  Build-Catalog.ps1          validates packages and builds the site
  categories.json            the category list (maintainers can extend it)
  rules.psd1                 banned patterns, size limits, analyzer exclusions
schema/catalog.schema.json   JSON Schema for catalog.json
site-src/                    static site source (HTML, CSS, vanilla JS, vendored libraries)
templates/package/           starter package
tests/                       Pester tests for the build, with bad-package fixtures
.github/                     workflows, CODEOWNERS, PR and issue templates
IDEAS.md                     scripts people want, looking for an author
```

## Installing a package

Open the package page on the website, download the zip and extract it into your OpsKit `Custom/` folder,
so that you get `Custom/<PackageId>/module.psd1`. Restart OpsKit. In-app install from the catalog is planned.

Community scripts run with your permissions. Read the code before running it.

## Submitting a package

The short version:

1. Copy [`templates/package/`](templates/package/) to `packages/<YourPackageId>/` (PascalCase, unique).
2. Fill in `module.psd1`, rename `Script.ps1` to `Verb-Noun.ps1`, and write your scripts.
3. Test them in OpsKit, then run `./build/Build-Catalog.ps1 -ValidateOnly`.
4. Open a pull request and fill in the checklist.

The full guide is on the [Contribute page](https://konnerlester1015.github.io/OpsKit-Catalog/contribute.html) and in
[CONTRIBUTING.md](CONTRIBUTING.md). Looking for something to write? See [IDEAS.md](IDEAS.md).

## Running the build locally

You need PowerShell 7.4+ and PSScriptAnalyzer. Pester 5 is needed for the tests.

```powershell
Install-PSResource PSScriptAnalyzer, Pester -Scope CurrentUser

# Validate only (what CI does on a pull request)
./build/Build-Catalog.ps1 -ValidateOnly

# Validate and build the site into ./site
./build/Build-Catalog.ps1 -OutputPath site

# Build for a local preview server
./build/Build-Catalog.ps1 -OutputPath site -BaseUrl http://localhost:8080/
python -m http.server 8080 --directory site

# Check that a changed package had its version bumped
./build/Build-Catalog.ps1 -ValidateOnly -BaseRef origin/main

# Run the tests
Invoke-Pester ./tests
```

Useful switches: `-SkipAnalyzer` for a quick check, `-PassThru` to get the issues and catalog as objects,
`-RequireOverrideApproval` to treat banned-pattern overrides as errors (CI does this until a maintainer adds
the `override-approved` label).

The build never runs package code. It reads `module.psd1`, `$ScriptInfo` and `$WidgetInfo` from the PowerShell
syntax tree with `SafeGetValue()`, which only accepts plain values.

## What CI checks

| Check | Fails when |
| --- | --- |
| Package metadata | `module.psd1` is missing, has missing or invalid fields, an unknown category, or a non-semver version; the folder name is not a unique PascalCase id. |
| Script and widget metadata | A script has no top-level `$ScriptInfo` of plain values, a widget has no `$WidgetInfo`, or a script isn't named `Verb-Noun.ps1` with an approved verb. |
| Parsing | Any `.ps1` or `.psd1` has a parse error. |
| PSScriptAnalyzer | Any Error or Warning, except the excluded rules documented in [`build/rules.psd1`](build/rules.psd1). |
| Banned patterns | `Invoke-Expression`/`iex`, runtime code (`[scriptblock]::Create`, `Add-Type`), downloads (`DownloadString`, `iwr … \| iex`), `-EncodedCommand`, base64 payloads, turning off security tooling, hard-coded secrets, profile/startup persistence, `Set-ExecutionPolicy`, and `Write-Host`/`Read-Host`/`Format-*`. |
| Files and size | Anything other than `.ps1`, `.psd1`, `.md`; binary content; non-UTF-8 text; symlinks; more than 256 KB. |
| Version bump | Files in a package changed compared with `main` but `Version` was not raised. |
| catalog.json | The generated catalog doesn't match the schema. |

The PR workflow validates packages with the build script **from the base branch**, so a pull request can't
weaken the checks it's judged by. It writes a summary of what passed and failed to the job summary and adds
annotations on the offending lines.

A banned pattern can be allowed for one line with a comment that gives a reason:

```powershell
# opskit-allow DownloadCode: downloads the vendor's signed CSV feed, never executes it
```

Overrides fail CI until a maintainer reviews them and adds the `override-approved` label.

## catalog.json contract

`catalog.json` is what OpsKit reads to browse, install, update and uninstall packages, so its format is a
contract. It is described by [`schema/catalog.schema.json`](schema/catalog.schema.json) (JSON Schema 2020-12),
and every build is validated against it.

```json
{
  "schemaVersion": 1,
  "generated": "2026-11-07T12:00:00Z",
  "catalogUrl": "https://konnerlester1015.github.io/OpsKit-Catalog/",
  "categories": ["Active Directory", "..."],
  "packages": [
    {
      "id": "ActiveDirectory",
      "name": "Active Directory",
      "description": "Users, groups, computers and account health.",
      "version": "1.0.0",
      "author": "KonnerLester1015",
      "category": "Active Directory",
      "tags": ["active-directory", "users", "computers"],
      "requiresModules": ["ActiveDirectory"],
      "minOpsKitVersion": "0.1.0",
      "updated": "2026-11-07",
      "download": { "url": "https://…/packages/ActiveDirectory-1.0.0.zip", "sha256": "…", "size": 2871 },
      "sourceUrl": "https://github.com/KonnerLester1015/OpsKit-Catalog/tree/main/packages/ActiveDirectory",
      "readmeUrl": "https://…/src/ActiveDirectory/README.md",
      "files": [ { "path": "Get-LockedOutUser.ps1", "url": "https://…/src/ActiveDirectory/Get-LockedOutUser.ps1", "size": 1093 } ],
      "scripts": [
        {
          "id": "ActiveDirectory/Get-LockedOutUser",
          "file": "Get-LockedOutUser.ps1",
          "name": "Locked-out Users",
          "description": "Find accounts that are currently locked out.",
          "version": "0.1.0",
          "requiresAdmin": false,
          "requiresModules": [],
          "platforms": ["Windows"],
          "parameters": [ { "name": "Server", "type": "string", "mandatory": false, "helpMessage": null } ]
        }
      ],
      "widgets": [
        {
          "id": "ActiveDirectory/DomainController",
          "file": "Widgets/DomainController.ps1",
          "name": "Domain controller",
          "description": "Domain, DC and AD site this computer is using",
          "requiresModules": [],
          "platforms": ["Windows"],
          "refreshSeconds": 300
        }
      ]
    }
  ]
}
```

Rules for clients:

- Every URL is absolute, built from the GitHub Pages base URL.
- The zip contains the package folder itself (`ActiveDirectory/...`), so extracting it into an OpsKit scripts
  folder just works. Zips are deterministic: the same files always give the same SHA-256.
- `updated` is the date of the last git commit that touched the package folder.
- `platforms` empty means every platform. `helpMessage` is `null` when a parameter has none. `validateSet`
  appears only on parameters that have one.
- **Versioning:** new optional fields may be added within `schemaVersion: 1`, so clients must ignore fields
  they don't know. Removing or renaming a field, or changing its meaning, bumps `schemaVersion`.

Fields added on top of the original spec, all optional for clients: top-level `categories`; package `readmeUrl`;
`files[].size`; script `file`, `version`, `requiresModules`; parameter `validateSet`; widget `file`,
`requiresModules`, `platforms`, `refreshSeconds`.

## Licence

[MIT](LICENSE). By contributing a package you agree to license it under MIT.
