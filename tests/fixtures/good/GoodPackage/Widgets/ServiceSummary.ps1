$WidgetInfo = @{
    Name            = 'Services'
    Description     = 'Running service count'
    RequiresModules = @()
    Platforms       = @('Windows')
    RefreshSeconds  = 60
}

[ordered]@{ Services = 'n/a' }
