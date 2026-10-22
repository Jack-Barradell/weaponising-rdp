<#
.SYNOPSIS
Creates a scheduled task that runs whenever a user connects over RDP.

.DESCRIPTION
Registers a task with a "remote connect" session trigger for the given users,
running as either SYSTEM or the user who connected. Also enables RDP on the
machine unless you pass -SkipRdpEnable.

.PARAMETER TaskName
Name of the scheduled task.

.PARAMETER Users
Users to trigger on, as DOMAIN\user or .\user for local accounts. Separate
multiple users with commas, or use "all" to trigger for anyone.

.PARAMETER RunAs
SYSTEM to run as SYSTEM, or User to run as the user who connected.

.PARAMETER Execute
Program to run. A full command line is split into program and arguments,
and a .ps1 path is run through powershell.exe in a hidden window automatically.

.PARAMETER Argument
Arguments for the program, if you'd rather not put them in -Execute.

.PARAMETER WorkingDirectory
Working directory for the program.

.PARAMETER TaskPath
Task Scheduler folder to create the task in. Defaults to the root (\).

.PARAMETER Elevated
With -RunAs User, run with the user's highest privileges instead of limited.

.PARAMETER NLA
Turn Network Level Authentication on (Enabled), off (Disabled), or leave it
as it is (Unchanged, the default).

.PARAMETER AddToRemoteDesktopUsers
Add the named users to the local Remote Desktop Users group.

.PARAMETER SkipRdpEnable
Don't touch any RDP settings, just create the task.

.PARAMETER Force
Overwrite an existing task with the same name without asking.

.EXAMPLE
.\New-RdpConnectTask.ps1 -TaskName RdpTest -Users .\alice -RunAs User -Execute C:\Tools\test.ps1

Runs test.ps1 as alice whenever she connects over RDP.

.EXAMPLE
.\New-RdpConnectTask.ps1 -TaskName RdpAll -Users all -RunAs SYSTEM -Execute 'cmd.exe /c whoami > C:\Temp\who.txt'

Runs a command as SYSTEM whenever anyone connects.

.EXAMPLE
.\New-RdpConnectTask.ps1 -TaskName RdpTest -Users 'CORP\bob,CORP\carol' -RunAs User -Execute notepad.exe -AddToRemoteDesktopUsers -SkipRdpEnable

Adds bob and carol to Remote Desktop Users and creates the task, without changing any RDP settings.
#>

#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory)][string]$TaskName,
    [Parameter(Mandatory)][string[]]$Users,
    [Parameter(Mandatory)][ValidateSet('SYSTEM', 'User')][string]$RunAs,
    [Parameter(Mandatory)][string]$Execute,
    [string]$Argument,
    [string]$WorkingDirectory,
    [string]$TaskPath = '\',
    [switch]$Elevated,
    [ValidateSet('Unchanged', 'Enabled', 'Disabled')][string]$NLA = 'Unchanged',
    [switch]$AddToRemoteDesktopUsers,
    [switch]$SkipRdpEnable,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$tsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$rdpKey = "$tsKey\WinStations\RDP-Tcp"

function Set-Dword($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}

function Get-AccountName($sid) {
    ([Security.Principal.SecurityIdentifier]$sid).Translate([Security.Principal.NTAccount]).Value
}

function Resolve-User($name) {
    $name = $name.Trim()
    if ($name.StartsWith('.\')) { $name = "$env:COMPUTERNAME\$($name.Substring(2))" }
    try {
        $sid = ([Security.Principal.NTAccount]$name).Translate([Security.Principal.SecurityIdentifier])
    } catch {
        throw "Couldn't find user '$name', use DOMAIN\user or .\user"
    }
    if ($sid.Value -like 'S-1-5-32-*') { throw "'$name' is a group, not a user" }
    $sid.Translate([Security.Principal.NTAccount]).Value
}

function New-RdpTrigger($userId) {
    $class = Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskSessionStateChangeTrigger
    $trigger = New-CimInstance -CimClass $class -ClientOnly
    $trigger.StateChange = 3
    $trigger.Enabled = $true
    if ($userId) { $trigger.UserId = $userId }
    $trigger
}

$Users = $Users -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if (-not $Users) { throw 'No users given' }

$allUsers = 'all' -in $Users
if ($allUsers) {
    $who = 'any user'
} else {
    $accounts = @($Users | ForEach-Object { Resolve-User $_ } | Sort-Object -Unique)
    $who = $accounts -join ', '
}

if (-not $TaskPath.StartsWith('\')) { $TaskPath = "\$TaskPath" }
if (-not $TaskPath.EndsWith('\')) { $TaskPath = "$TaskPath\" }

$Execute = $Execute.Trim()
if ($Argument) {
    $Execute = $Execute.Trim('"')
} elseif (-not (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($Execute.Trim('"'))) -PathType Leaf)) {
    if ($Execute -match '^"([^"]+)"\s*(.*)$' -or $Execute -match '^(\S+)\s+(.+)$') {
        $Execute = $Matches[1]
        $Argument = $Matches[2].Trim()
    } else {
        $Execute = $Execute.Trim('"')
    }
}

$exe = [Environment]::ExpandEnvironmentVariables($Execute)
if ($Execute -like '*.ps1') {
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        Write-Host "Warning: can't find $Execute from here, make sure the task's account can reach it"
    }
    $Argument = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Execute`" $Argument".Trim()
    $Execute = 'powershell.exe'
} elseif (-not (Test-Path -LiteralPath $exe -PathType Leaf) -and -not (Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue)) {
    Write-Host "Warning: can't find $Execute from here, make sure the task's account can reach it"
}

if (-not $SkipRdpEnable) {
    $os = (Get-CimInstance Win32_OperatingSystem).Caption
    if ($os -match 'Home') { Write-Host "Warning: $os doesn't support incoming RDP, so the task will never trigger" }
}

$existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
if ($existing -and -not $Force) {
    $answer = Read-Host "$TaskPath$TaskName already exists, overwrite it? (y/n)"
    if ($answer -ne 'y') { return }
}

if (-not $SkipRdpEnable) {
    Write-Host 'Enabling RDP'
    Set-Dword $tsKey fDenyTSConnections 0

    $policy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -ErrorAction SilentlyContinue
    if ($policy.fDenyTSConnections -eq 1) {
        Write-Host 'Warning: RDP is turned off by GPO ("Allow users to connect remotely"), which will override this'
    }

    if ($NLA -eq 'Enabled') { Set-Dword $rdpKey UserAuthentication 1 }
    if ($NLA -eq 'Disabled') { Set-Dword $rdpKey UserAuthentication 0 }

    $rules = @(Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction SilentlyContinue)
    if ($rules) {
        $rules | Enable-NetFirewallRule
    } else {
        Write-Host "Warning: no built-in RDP firewall rules found, you'll need to open the port yourself"
    }

    $port = (Get-ItemProperty $rdpKey -ErrorAction SilentlyContinue).PortNumber
    if ($port -and $port -ne 3389) {
        Write-Host "Warning: RDP is on port $port but the firewall rules only cover 3389"
    }

    $svc = Get-Service TermService
    if ($svc.StartType -eq 'Disabled') { Set-Service TermService -StartupType Manual }
    if ($svc.Status -ne 'Running') { Start-Service TermService }
}

if ($AddToRemoteDesktopUsers -and -not $allUsers) {
    $group = Get-LocalGroup -SID 'S-1-5-32-555'
    foreach ($account in $accounts) {
        try {
            Add-LocalGroupMember -Group $group -Member $account -ErrorAction Stop
            Write-Host "Added $account to $($group.Name)"
        } catch {
            if ($_.FullyQualifiedErrorId -notlike 'MemberExists*') {
                Write-Host "Couldn't add ${account}: $($_.Exception.Message)"
            }
        }
    }
}

if ($allUsers) {
    $triggers = @(New-RdpTrigger)
} else {
    $triggers = @($accounts | ForEach-Object { New-RdpTrigger $_ })
}

if ($RunAs -eq 'SYSTEM') {
    $principal = New-ScheduledTaskPrincipal -UserId (Get-AccountName 'S-1-5-18') -LogonType ServiceAccount -RunLevel Highest
    $runAsText = 'SYSTEM'
} else {
    $level = if ($Elevated) { 'Highest' } else { 'Limited' }
    $principal = New-ScheduledTaskPrincipal -GroupId (Get-AccountName 'S-1-5-32-545') -RunLevel $level
    $runAsText = 'the connecting user'
}

$actionArgs = @{ Execute = $Execute }
if ($Argument) { $actionArgs.Argument = $Argument }
if ($WorkingDirectory) { $actionArgs.WorkingDirectory = $WorkingDirectory }

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Parallel
$task = New-ScheduledTask -Action (New-ScheduledTaskAction @actionArgs) -Principal $principal -Trigger $triggers -Settings $settings -Description "Runs on RDP connect for $who"
Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -InputObject $task -Force | Out-Null

Write-Host "Created $TaskPath$TaskName"
Write-Host "Runs $Execute $Argument as $runAsText when $who connects over RDP"