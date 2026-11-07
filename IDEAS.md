# Package ideas

Script ideas for catalog packages, moved from the OpsKit repo. Entries marked ✅ already exist in `packages/`.

## Active Directory
`Modules/ActiveDirectory` · needs RSAT `ActiveDirectory`

| Script                     | What it does                                                       |
| -------------------------- | ------------------------------------------------------------------ |
| ✅ Get-LockedOutUser       | Locked-out accounts with lockout time and last bad password        |
| ✅ Find-StaleComputer      | Enabled computers with no logon in N days                          |
| Find-StaleUser             | Enabled users with no logon in N days, excluding service accounts  |
| Get-PasswordExpiry         | Users whose passwords expire in the next N days                    |
| Get-UserDetail             | Everything about one user: groups, manager, lockout, last logon    |
| Unlock-UserAccount         | Search for a user and unlock them (helpdesk favourite)             |
| Reset-UserPassword         | Reset with a generated password, force change at next logon        |
| Compare-UserGroup          | Group membership difference between two users ("make Bob like Alice") |
| Copy-UserGroupMembership   | Apply one user's groups to another, with a preview                 |
| Get-GroupMemberReport      | Recursive members of a group, exportable                           |
| Get-PrivilegedGroupReport  | Members of Domain/Enterprise/Schema Admins and other tier-0 groups |
| Find-EmptyGroup            | Groups with no members                                             |
| Get-DomainControllerHealth | Replication, dcdiag summary, FSMO holders, time sync               |
| Get-ADReplicationStatus    | Replication failures per partner                                   |
| Move-StaleComputer         | Move stale computers to a disabled OU, with a report               |
| Get-GPOReport              | Unlinked, empty or disabled GPOs (needs `GroupPolicy`)             |
| Get-LAPSPassword           | Retrieve a LAPS password for a computer (with audit log line)      |
| Get-BitLockerRecoveryKey   | Look up a BitLocker recovery key by computer or key ID             |

## Microsoft 365 / Entra ID
`Modules/Microsoft365` · needs `Microsoft.Graph.*`, `ExchangeOnlineManagement`, `MicrosoftTeams`

| Script                     | What it does                                                       |
| -------------------------- | ------------------------------------------------------------------ |
| ✅ Get-EntraUserDetail     | Account status, sign-in, licences and manager for one user         |
| Get-LicenseReport          | Licences purchased vs assigned vs available per SKU                |
| Find-UnusedLicense         | Licensed users who haven't signed in for N days                    |
| Get-MfaStatusReport        | Users and their registered authentication methods                  |
| Get-RiskyUserReport        | Users flagged by Identity Protection                               |
| Get-SignInFailures         | Recent failed sign-ins for a user with error reasons               |
| Get-GuestUserReport        | Guests, who invited them, and last sign-in                         |
| Get-AppSecretExpiry        | App registrations with secrets/certificates expiring soon          |
| Get-ConditionalAccessReport | CA policies, state and assignments                                |
| Invoke-UserOffboarding     | Block sign-in, revoke sessions, remove licences, convert mailbox, hand over OneDrive (confirm each step) |
| New-UserOnboarding         | Create user, assign licences and groups from a template            |
| Get-MailboxSizeReport      | Mailbox and archive sizes, quota warnings                          |
| Get-MailboxPermission      | Full access / send as / send on behalf for a mailbox               |
| Set-MailboxForwarding      | Set or clear forwarding, with a confirmation                       |
| Find-ExternalForwarding    | Mailboxes and inbox rules forwarding outside the tenant            |
| Get-TeamsOwnerlessTeam     | Teams with no owner or one owner                                   |
| Get-SharePointExternalShare | Externally shared sites and files                                 |

## VMware / Virtualization
`Modules/VMware` · needs `VMware.PowerCLI` (Hyper-V scripts need `Hyper-V`)

| Script                     | What it does                                                       |
| -------------------------- | ------------------------------------------------------------------ |
| ✅ Get-VMSnapshotReport    | Snapshots older than N days with size and age                      |
| Get-VMInventory            | VMs with CPU, memory, disk, OS, host, cluster, tools status        |
| Get-HostHealth             | ESXi host state, alarms, CPU/memory use, uptime                    |
| Get-DatastoreUsage         | Datastore capacity and free space with a bar chart                 |
| Find-PoweredOffVM          | VMs powered off for N days                                         |
| Get-VMToolsStatus          | VMs with outdated or missing VMware Tools                          |
| Remove-OldSnapshot         | Delete snapshots older than N days, with a preview and confirmation |
| Get-OrphanedVmdk           | Disk files not attached to any VM                                  |
| Get-HyperVInventory        | Hyper-V VMs, checkpoints, integration services                     |


## Extensions

### ServiceNow
`Extensions/ServiceNow`

| Script                     | What it does                                                       |
| -------------------------- | ------------------------------------------------------------------ |
| ✅ Test-ServiceNowConnection | Reachability check, saves the instance URL                       |
| Get-MyIncident             | Open incidents assigned to me or my group                          |
| Get-Incident               | Look up an incident by number with notes                           |
| New-Incident               | Raise an incident from a template                                  |
| Add-WorkNote               | Add a work note (e.g. paste script output into a ticket)           |
| Get-ChangeCalendar         | Upcoming changes this week                                         |
| Get-CmdbCi                 | Look up a configuration item by name                               |

### Rubrik
`Extensions/Rubrik` · `RubrikSecurityCloud` module

| Script                     | What it does                                                       |
| -------------------------- | ------------------------------------------------------------------ |
| ✅ Test-RubrikConnection   | Reachability check, saves the URL                                  |
| Get-SlaComplianceReport    | Objects out of SLA compliance                                      |
| Get-BackupStatus           | Last successful backup per VM/host/database                        |
| Get-FailedJob              | Failed jobs in the last N hours                                    |
| Start-OnDemandSnapshot     | Take an on-demand snapshot of an object (with confirmation)        |

### Varonis
`Extensions/Varonis`

| Script                     | What it does                                                       |
| -------------------------- | ------------------------------------------------------------------ |
| ✅ Test-VaronisConnection  | Reachability check, saves the URL                                  |
| Get-Alert                  | Recent alerts by severity                                          |
| Get-UserAccessReport       | What a user can access                                             |
| Get-StaleDataReport        | Folders not accessed in N days                                     |
| Get-OpenAccessReport       | Folders open to Everyone / Domain Users                            |

### CrowdStrike Falcon
`Extensions/CrowdStrike` · `PSFalcon` module

| Script                     | What it does                                                       |
| -------------------------- | ------------------------------------------------------------------ |
| ✅ Test-FalconConnection   | Reachability check, saves the API URL                              |
| Find-FalconHost            | Look up a host: sensor version, last seen, policies                |
| Get-Detection              | New detections by severity                                         |
| Get-SensorHealth           | Hosts with outdated sensors or not seen for N days                 |
| Invoke-HostContainment     | Contain/lift containment for a host (with confirmation and reason) |
| Get-RtrSession             | Start a Real Time Response session (power users)                   |

