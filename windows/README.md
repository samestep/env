# Windows

A Windows 11 guest that runs **inside** the `x86_64-linux` VM (`sandbox-amd64`), using
[dockur/windows](https://github.com/dockur/windows) — a container that runs Windows in
QEMU/KVM and fully automates the download + unattended install. Because it's nested
virtualization (Windows-in-KVM-in-the-Linux-VM), the Linux VM must expose `/dev/kvm`;
both of this repo's Linux VMs already do (the libvirt guest has nested KVM, and the Lima
guest is created with `--set '.nestedVirtualization = true'`).

> [!NOTE]
> This works on the **x86_64** Linux VM. It does **not** work on the `aarch64` Linux VM —
> see [ARM64](#arm64-doesnt-work) at the bottom for why.

## Setup

The [`compose.yml`](compose.yml) here creates a Windows 11 Pro guest with a local admin
account `agent` / `password`, and publishes three ports: the web viewer (`8006`), RDP
(`3389`), and SSH (`2222`, once you set up OpenSSH — see below). The `storage/` directory
holds the VM disk and is git-ignored.

```sh
mkdir -p ~/windows && cp compose.yml ~/windows/ && cd ~/windows
docker compose up -d
```

The container downloads the official Microsoft ISO and installs Windows completely
unattended (partition, skip the Microsoft-account/OOBE prompts, create the local admin,
enable RDP). It takes roughly 30–60 minutes; watch progress at
<http://localhost:8006> (tunnel it with `ssh -L 8006:localhost:8006 sandbox-amd64`).

## Access

Once installed, from the host machine over the tailnet:

- **Web viewer** (works during install too): tunnel `8006` and open the browser.
- **RDP**: tunnel `3389` (`ssh -L 3389:localhost:3389 sandbox-amd64`) and connect with any
  RDP client to `localhost:3389` as `agent` / `password`.
- **SSH → PowerShell**: once OpenSSH is set up (below), it behaves exactly like the Linux
  nested-SSH hops:

  ```sh
  ssh sandbox-amd64                # tailnet
  ssh -p 2222 agent@localhost      # into the Windows guest -> PowerShell
  ```

  or as a one-liner: `ssh -J sandbox-amd64 -p 2222 agent@localhost`.

## Enabling SSH → PowerShell

dockur's Windows image doesn't ship an SSH server, so this is a manual one-time setup.
Run everything below in an **elevated PowerShell** inside the guest (open one via RDP, or
Win+X → "Terminal (Admin)").

Installing OpenSSH via the Windows "Feature on Demand" (`Add-WindowsCapability`) is
unreliable here — it pulls from Windows Update over the guest's slow NAT and often stalls.
Install it straight from the official release instead:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
iwr 'https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip' -OutFile C:\o.zip -UseBasicParsing
Expand-Archive C:\o.zip C:\ -Force
powershell -ExecutionPolicy Bypass -File C:\OpenSSH-Win64\install-sshd.ps1
& C:\OpenSSH-Win64\ssh-keygen.exe -A                       # generate host keys
# host keys must not be world-readable or sshd refuses to start:
Get-ChildItem C:\ProgramData\ssh\ssh_host_*_key | ForEach-Object {
  icacls $_.FullName /inheritance:r /grant SYSTEM:F /grant BUILTIN\Administrators:F
}
# make PowerShell the default shell for SSH sessions:
New-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
  -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force
```

### Running sshd (the tricky part)

On this image the normal `sshd` **Windows service crashes** when run as `LocalSystem`
(`get_passwd: lookup_sid() failed: 1332` — an account/SID-mapping quirk of the minimal
dockur image). Running `sshd.exe` as the `agent` user works instead, so run it from a
**scheduled task at logon** (dockur auto-logs-in `agent`, so this starts sshd on every
boot):

```powershell
Set-Service sshd -StartupType Disabled                     # don't let the broken service fight for :22
$a = New-ScheduledTaskAction -Execute C:\OpenSSH-Win64\sshd.exe
$t = New-ScheduledTaskTrigger -AtLogOn
$p = New-ScheduledTaskPrincipal -UserId agent -RunLevel Highest
Register-ScheduledTask sshd-agent -Action $a -Trigger $t -Principal $p -Force
```

But a non-`SYSTEM` sshd authenticates fine and then **can't create the login session**
(the SSH channel closes right after "Authenticated") because a normal admin lacks the
privilege to create a primary token. Grant it to `agent` (takes effect next logon):

```powershell
secedit /export /cfg C:\s.inf /areas USER_RIGHTS | Out-Null
(gc C:\s.inf) `
  -replace 'SeAssignPrimaryTokenPrivilege = ','SeAssignPrimaryTokenPrivilege = agent,' `
  -replace 'SeIncreaseQuotaPrivilege = ','SeIncreaseQuotaPrivilege = agent,' | Set-Content C:\s2.inf
secedit /configure /db C:\s.sdb /cfg C:\s2.inf /areas USER_RIGHTS
Restart-Computer -Force
```

After the reboot, `ssh -p 2222 agent@localhost` drops you into PowerShell.

### Passwordless (key-based) login

`agent` is an administrator, so Win32-OpenSSH reads authorized keys from
`C:\ProgramData\ssh\administrators_authorized_keys` (**not** `~/.ssh/authorized_keys`),
and that file must be owned/readable only by SYSTEM and Administrators:

```powershell
# paste your public key as the content:
Set-Content C:\ProgramData\ssh\administrators_authorized_keys -Value 'ssh-ed25519 AAAA... you@host' -Encoding ascii
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant SYSTEM:F /grant BUILTIN\Administrators:F
```

With `sandbox-amd64`'s key installed this way, the whole chain
(you → `sandbox-amd64` via Tailscale SSH → guest via key) is passwordless.

## ARM64 doesn't work

Running the equivalent (`dockurr/windows-arm`) inside the `aarch64` Linux VM
**hangs at the EDK2 → Windows-ARM bootloader handoff** ("Start boot option") and never
reaches the installer, under the doubly-nested Apple-Silicon → Lima-Ubuntu → KVM stack.
Ruled out exhaustively — all of these hang identically:

- dockur's EDK2 firmware, and stock TianoCore/AAVMF firmware
- `gic-version=max` and `gic-version=3`
- USB vs. virtio-SCSI CD-ROM install media
- dockur, and a hand-rolled `qemu-system-aarch64` invocation

KVM acceleration is confirmed active (not TCG), and it's not a reboot loop — the guest
simply wedges the moment the Windows-ARM UEFI bootloader starts executing. Nested *Linux*
guests and nested *x86* Windows both work fine on the same hardware, so this appears to be
a genuine nested-virtualization limitation specific to Windows-on-ARM at this nesting
depth. See [dockur/windows#1548](https://github.com/dockur/windows/issues/1548) for others
hitting the same wall. If you actually need ARM Windows, run it un-nested (directly on the
Mac host via UTM/Parallels) instead.
