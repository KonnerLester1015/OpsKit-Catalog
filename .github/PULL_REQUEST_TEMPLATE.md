## What this pull request does

<!-- New package, update to a package, or a change to the catalog itself. One package per pull request, please. -->

## Package checklist

- [ ] The folder name is a unique PascalCase id, and `module.psd1` has every field filled in.
- [ ] I bumped `Version` in `module.psd1` (updates only).
- [ ] Every script is named `Verb-Noun.ps1` with an approved verb and has a `$ScriptInfo` of plain values.
- [ ] Scripts return objects and use the OpsKit helpers, not `Write-Host`, `Read-Host` or `Format-Table`.
- [ ] `Get-`, `Test-` and `Find-` scripts are read-only. Anything that changes something asks first.
- [ ] Widgets are fast and read-only, with no prompts and no sign-ins.
- [ ] No hard-coded secrets, tenant ids, server names or other details from my environment.
- [ ] I tested every script and widget in OpsKit.
- [ ] `./build/Build-Catalog.ps1 -ValidateOnly` passes locally.
- [ ] I wrote this code or have the right to share it, and I agree to license it under MIT.

## How I tested it

<!-- OpsKit version, PowerShell version, OS, and what you ran it against. -->

## Overrides

<!-- If you used `# opskit-allow <Rule>: <reason>`, explain why here. A maintainer has to approve it with the override-approved label. -->
