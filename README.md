# RDP Lab Tooling

## Summary

This is the code released to accompany my blog post of how attackers can exploit RDP on Windows, and how defenders can protect against it. For details please see the detailed blog post at [https://thehackingblog.com/2026/10/22/weaponising-rdp/](https://thehackingblog.com/2026/10/22/weaponising-rdp/) 

---

## rdpgen.py

Generates a `.rdp` file from the command line, or prints it with `--print`. Defaults turn on full local-resource redirection (drives, clipboard, printers, smart cards, USB, camera, mic)

```bash
python rdpgen.py -h <host> [options]
```

```bash
python rdpgen.py -h 10.10.10.217 
python rdpgen.py -h server01 -d CORP -u alice -o alice.rdp
python rdpgen.py -h 10.0.0.5 --gateway gw.corp.example
python rdpgen.py -h 10.0.0.5 --remoteapp '||calc' --app-name Calculator
```

| Option | Purpose |
|---|---|
| `-h`, `--host` | Target host or IP. **Required.** |
| `-p`, `--port` | RDP port. Added to the address only when not 3389. |
| `-u`/`-d` | Username / domain (prefilled as `DOMAIN\user`). |
| `-o`, `--output` | Output path. Defaults to `<host>.rdp`. |
| `--gateway` | RD Gateway hostname; sets the gateway keys. |
| `--remoteapp` / `--app-name` / `--app-args` / `--app-file` / `--app-dir` | RemoteApp program, display name, args, file, working dir. |
| `--set KEY:VAL` | Add or override any raw `.rdp` key (repeatable). |
| `--print` | Write to stdout instead of a file. |

---

## New-RdpConnectTask.ps1

Registers a scheduled task that fires on a RDP connection, running as SYSTEM or the connecting user. Unless `-SkipRdpEnable` is set, it also enables RDP.

```powershell
.\New-RdpConnectTask.ps1 -TaskName <name> -Users <user|all> -RunAs <SYSTEM|User> -Execute <program> [options]
```

```powershell
.\New-RdpConnectTask.ps1 -TaskName RdpTest -Users .\alice -RunAs User -Execute C:\Tools\test.ps1
.\New-RdpConnectTask.ps1 -TaskName RdpAll -Users all -RunAs SYSTEM -Execute 'cmd.exe /c whoami > C:\Temp\who.txt'
.\New-RdpConnectTask.ps1 -TaskName RdpTest -Users 'CORP\bob,CORP\carol' -RunAs User -Execute notepad.exe -AddToRemoteDesktopUsers -SkipRdpEnable
```

| Parameter | Purpose |
|---|---|
| `-TaskName` | Name of the task. |
| `-Users` | `DOMAIN\user` or `.\user`, comma-separated, or `all` for anyone. |
| `-RunAs` | `SYSTEM` or `User` (the connecting user). |
| `-Execute` / `-Argument` | Program to run / its arguments. |
| `-WorkingDirectory` | Working directory for the action. |
| `-TaskPath` | Task Scheduler folder. Defaults to `\`. |
| `-Elevated` | With `-RunAs User`, run at highest privileges. |
| `-NLA` | `Enabled`, `Disabled`, or `Unchanged` (default). |
| `-AddToRemoteDesktopUsers` | Add named users to the Remote Desktop Users group. |
| `-SkipRdpEnable` | Create the task only; leave RDP settings alone. |
| `-Force` | Overwrite an existing task without prompting. |

---

## Task.ps1

Payload script for the scheduled task. Runs inside the connecting user's RDP session, enumerates redirected `\\tsclient\` drives, identifies the client-side user profile, logs reconnaissance to `C:\Temp\<timestamp>\`, drops files from a staging directory to the client via tsclient write-back, and creates a Startup shortcut pointing to the dropped payload.

Configure the variables at the top of the script before use:

```powershell
$baseOutputDir = "C:\Temp"          # server-side log directory
$copyFromDir   = "C:\Temp\copyfrom" # server-side staging dir — contents copied to client
$lnkName       = "Demo.lnk"        # shortcut filename placed in Startup
$lnkTargetName = "calc.exe"        # executable the shortcut points to (must exist in $copyFromDir)
```

### Output

Each run creates `C:\Temp\<yyyy-MM-dd-HH-mm-ss>\` containing:

| File | Contents |
|---|---|
| `redirectedDrives.txt` | All `\\tsclient\` mounts found, with `HasUsers` / `HasWindows` / `HasProgramFiles` flags |
| `profiles.txt` | User profiles under `\Users`, with readable/writable status and last-write time |
| `documents.txt` | Directory listing of identified user's Documents |
| `downloads.txt` | Directory listing of identified user's Downloads |
| `desktop.txt` | Directory listing of identified user's Desktop |
| `droppercheck.txt` | Contents of the drop directory on the client after copy |
| `startupcheck.txt` | Contents of the client's Startup folder after shortcut creation |


## Disclaimer

All material presented in this repository is provided for use in authorised testing and education only.