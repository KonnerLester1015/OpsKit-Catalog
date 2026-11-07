@{
    Name             = 'My Package'              # menu entry name in OpsKit
    Description      = 'One line about what the scripts in this package do.'
    Version          = '1.0.0'                   # semver; bump it whenever any file changes
    Author           = 'your-github-username'
    Category         = 'Other'                   # one of the names in build/categories.json
    Tags             = @('example')              # lowercase, dashes allowed
    RequiresModules  = @()                       # modules every script needs, e.g. @('ActiveDirectory')
    MinOpsKitVersion = '0.1.0'
}
