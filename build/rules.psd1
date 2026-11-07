@{
    # Size and file type limits for a package folder.
    MaxPackageSizeKB  = 256
    AllowedExtensions = @('.ps1', '.psd1', '.md')

    # Fields in module.psd1. All of them are required.
    ManifestFields    = @('Name', 'Description', 'Version', 'Author', 'Category', 'Tags', 'RequiresModules', 'MinOpsKitVersion')

    # Fields in $ScriptInfo. Required ones fail the build when missing, the rest are optional.
    ScriptInfoRequired = @('Name', 'Description', 'Version', 'Author')
    ScriptInfoOptional = @('Tags', 'RequiresModules', 'RequiresAdmin', 'Platforms')

    # Fields in $WidgetInfo.
    WidgetInfoRequired = @('Name', 'Description')
    WidgetInfoOptional = @('RequiresModules', 'Platforms', 'RefreshSeconds')

    Platforms         = @('Windows', 'Linux', 'macOS')

    # PSScriptAnalyzer runs with its default rules and fails the build on any Error or Warning,
    # except for the rules below. Each exclusion needs a reason.
    AnalyzerExcludeRules = @(
        # Writing to the host is banned outright by the HostOutput rule below, with a clearer message.
        'PSAvoidUsingWriteHost'
        # OpsKit requires PowerShell 7.4+, which reads UTF-8 files without a BOM correctly.
        'PSUseBOMForUnicodeEncodedFile'
    )

    # Individual findings to ignore, matched by rule name and a regex on the message.
    AnalyzerIgnore = @(
        # $ScriptInfo and $WidgetInfo are read by OpsKit, not by the script itself.
        @{ Rule = 'PSUseDeclaredVarsMoreThanAssignments'; MessagePattern = "'(ScriptInfo|WidgetInfo)'" }
    )

    # Banned patterns. Each regex runs over .ps1 and .psd1 files with comments removed, so
    # mentioning a command in a comment is fine. A line can be allowed with an override comment
    # on the same line or the line above:
    #
    #     # opskit-allow DownloadCode: fetches the vendor's signed CSV feed, never executes it
    #
    # Overrides need a reason and must be approved by a maintainer (the "override-approved" label).
    BannedPatterns = @(
        @{
            Id      = 'InvokeExpression'
            Pattern = '(?i)(?<![\w-])(Invoke-Expression|iex)(?![\w-])'
            Message = 'Invoke-Expression (iex) runs strings as code. Call commands directly and pass parameters with splatting.'
        }
        @{
            Id      = 'DynamicCode'
            Pattern = '(?i)\[scriptblock\]::Create\b|\bInvokeCommand\.(InvokeScript|NewScriptBlock)\b|(?<![\w-])Add-Type(?![\w-])'
            Message = 'Building or compiling code at runtime ([scriptblock]::Create, InvokeScript, Add-Type) hides what a script does.'
        }
        @{
            Id      = 'DownloadCode'
            Pattern = '(?i)\b(DownloadString|DownloadFile|DownloadData)(Async)?\b|\bNet\.WebClient\b|(?<![\w-])Start-BitsTransfer(?![\w-])|(?<![\w-])(iwr|irm|Invoke-WebRequest|Invoke-RestMethod)\b[^\r\n]*\|\s*(&|\.\s|powershell\b|pwsh\b)'
            Message = 'Packages must not download files or code at runtime. Everything a script runs must be in the package so it can be reviewed.'
        }
        @{
            Id      = 'EncodedCommand'
            Pattern = '(?i)(?<![\w-])-(EncodedCommand|EncodedArguments|enc|ec)(?![\w-])|\b(pwsh|powershell)(\.exe)?\b[^\r\n]*\s-e\s'
            Message = '-EncodedCommand hides the code being run. Run the commands directly.'
        }
        @{
            Id      = 'Base64Payload'
            Pattern = '(?i)FromBase64String[^\r\n]*(\||\bInvoke|\bscriptblock|::Load\b|\biex\b)|\[(System\.)?Reflection\.Assembly\]::Load(File|From)?\s*\(|[''"][A-Za-z0-9+/]{200,}={0,2}[''"]'
            Message = 'Decoding and running base64 payloads or loading assemblies from memory is not allowed.'
        }
        @{
            Id      = 'DisableSecurity'
            Pattern = '(?i)(?<![\w-])Set-MpPreference\b[^\r\n]*-Disable|(?<![\w-])Add-MpPreference\b[^\r\n]*-Exclusion|\bAmsiUtils\b|\bamsiInitFailed\b|(?<![\w-])Set-NetFirewallProfile\b[^\r\n]*-Enabled\s+(\$false|false|0)\b|\bnetsh\b[^\r\n]*\bfirewall\b[^\r\n]*\boff\b|(?<![\w-])Stop-Service\b[^\r\n]*\b(WinDefend|Sense|MsMpSvc|CSFalconService)\b'
            Message = 'Packages must not turn off or weaken security tooling (Defender, AMSI, firewall, EDR agents).'
        }
        @{
            Id      = 'HardcodedSecret'
            Pattern = '(?i)\w*(password|passwd|secret|token|apikey|api_key|accesskey|access_key|privatekey|private_key|clientsecret|client_secret|connectionstring)\w*\s*=\s*[''"][^''"\s$]{3,}[''"]|(?<![\w-])-(Password|Secret|Token|ApiKey|AccessToken|ClientSecret)\s+[''"][^''"$]+[''"]|(?<![\w-])ConvertTo-SecureString(?=[^\r\n]*-AsPlainText)\s+((-AsPlainText|-Force|-String)\s+)*[''"][^''"$]+[''"]|[''"][^''"$\r\n]+[''"]\s*\|\s*ConvertTo-SecureString\b'
            Message = 'Looks like a hard-coded secret. Prompt for credentials (Get-Credential, Read-OpsKitText) or read them from a secret store.'
        }
        @{
            Id      = 'PersistenceLocation'
            Pattern = '(?i)\$PROFILE\b|\bprofile\.ps1\b|\\Start Menu\\Programs\\Startup\b|\bshell:(common )?startup\b|SpecialFolder\]::(Common)?Startup\b|GetFolderPath\(\s*[''"](Common)?Startup[''"]|\\CurrentVersion\\Run(Once)?\b'
            Message = 'Packages must not write to PowerShell profiles or startup locations (Startup folder, Run keys).'
        }
        @{
            Id      = 'ExecutionPolicy'
            Pattern = '(?i)(?<![\w-])Set-ExecutionPolicy(?![\w-])|-ExecutionPolicy\s+(Bypass|Unrestricted)\b'
            Message = 'Packages must not change or bypass the execution policy.'
        }
        @{
            Id      = 'HostOutput'
            Pattern = '(?i)(?<![\w-])(Write-Host|Read-Host|Format-Table|Format-List|Out-GridView)(?![\w-])'
            Message = 'Use OpsKit helpers instead (Write-OpsKitStatus, Read-OpsKitText, Show-OpsKitTable) and return objects, so output works in tables and exports.'
        }
    )

    # Commands that change something. Get-, Test- and Find- scripts that call them get a warning,
    # because those scripts must be read-only. OpsKit's own helpers (*-OpsKit*) are not counted.
    StateChangingVerbs = @('Set', 'New', 'Remove', 'Add', 'Clear', 'Disable', 'Enable', 'Move', 'Rename', 'Reset',
        'Restart', 'Start', 'Stop', 'Suspend', 'Resume', 'Unlock', 'Lock', 'Install', 'Uninstall', 'Update',
        'Grant', 'Revoke', 'Block', 'Unblock', 'Register', 'Unregister', 'Publish', 'Unpublish')
}
