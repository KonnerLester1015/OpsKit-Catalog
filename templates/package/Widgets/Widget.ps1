<#
.SYNOPSIS
    Home screen widget: free space on the drive PowerShell runs from.
.NOTES
    Rename this file to a PascalCase name, for example Widgets/SystemDrive.ps1.
    Widgets refresh on a timer, so keep them fast and read-only: no prompts and no sign-ins.
    Return an [ordered] hashtable of label/value rows. A value can be text, or
    @{ Text = '...'; Level = 'Success' | 'Warning' | 'Error' | 'Muted' } for colour.
#>

$WidgetInfo = @{
    Name            = 'System drive'
    Description     = 'Free space on the system drive'
    RequiresModules = @()
    Platforms       = @()
    RefreshSeconds  = 300
}

$drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($PSHOME))
$freePercent = [math]::Round($drive.AvailableFreeSpace / $drive.TotalSize * 100)
$level = if ($freePercent -lt 10) { 'Error' } elseif ($freePercent -lt 20) { 'Warning' } else { 'Success' }

[ordered]@{
    Drive = $drive.Name
    Free  = @{ Text = '{0}% ({1:N0} GB)' -f $freePercent, ($drive.AvailableFreeSpace / 1GB); Level = $level }
}
