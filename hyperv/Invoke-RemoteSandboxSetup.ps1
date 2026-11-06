<#
Runs New-SandboxVMs.ps1 against the beef.taco.moe Hyper-V host without ever
cloning this repo onto beef. Copies just the script + this run's rendered
kickstart files to a temp dir on beef over scp, executes it there over ssh,
then removes the temp dir — win or fail.

Uses plain ssh/scp rather than PowerShell Remoting: beef only has PS 5.1
(no pwsh), and PS Remoting over SSH needs pwsh on both ends.

beef.taco.moe's ~/.ssh/config entry sets `RemoteCommand powershell`, which
hijacks any one-off command passed on the ssh command line unless
overridden — every ssh call below passes -o RemoteCommand=none for that
reason.

Usage: ./Invoke-RemoteSandboxSetup.ps1 -IsoPath 'V:\ISOs\rhel-10.2-x86_64-dvd.iso' `
         -VhdRoot 'V:\Hyper-V' -SwitchName 'Lab'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$VhdRoot,
    [Parameter(Mandatory)][string]$SwitchName,
    [int]$DiskSizeGB = 100,
    [string]$HypervHost = "beef.taco.moe",
    [string]$KickstartDir = (Join-Path $PSScriptRoot "..\kickstart\rendered"),
    [string]$RemoteTempDir = 'C:\Users\Ryan\AppData\Local\Temp\rke2-sandbox-setup'
)

$ErrorActionPreference = "Stop"

function Invoke-RemoteCommand {
    param([Parameter(Mandatory)][string]$Command)

    & ssh -o RemoteCommand=none $HypervHost "powershell -NoProfile -Command `"$Command`""
    if ($LASTEXITCODE -ne 0) {
        throw "Remote command failed (exit $LASTEXITCODE): $Command"
    }
}

$localScript = Join-Path $PSScriptRoot "New-SandboxVMs.ps1"
if (-not (Test-Path $localScript)) {
    throw "New-SandboxVMs.ps1 not found next to this script: $localScript"
}

$ksFiles = @(Get-ChildItem -Path $KickstartDir -Filter "*.ks" -ErrorAction SilentlyContinue)
if ($ksFiles.Count -eq 0) {
    throw "No .ks files in $KickstartDir — render them first: ansible-playbook -i inventory/sandbox/hosts.yml kickstart/render_kickstarts.yml"
}

Write-Host "Staging on ${HypervHost}: $RemoteTempDir" -ForegroundColor Cyan
Invoke-RemoteCommand "New-Item -ItemType Directory -Force -Path '$RemoteTempDir' | Out-Null"

try {
    $copyPaths = @($localScript) + $ksFiles.FullName
    & scp -o RemoteCommand=none @copyPaths "${HypervHost}:${RemoteTempDir}/"
    if ($LASTEXITCODE -ne 0) {
        throw "scp failed (exit $LASTEXITCODE)"
    }

    Write-Host "Running New-SandboxVMs.ps1 on ${HypervHost}" -ForegroundColor Cyan
    $remoteScript = "$RemoteTempDir\New-SandboxVMs.ps1"
    $remoteCmd = "& '$remoteScript' -IsoPath '$IsoPath' -VhdRoot '$VhdRoot' -SwitchName '$SwitchName' -DiskSizeGB $DiskSizeGB -KickstartDir '$RemoteTempDir'"
    Invoke-RemoteCommand $remoteCmd
}
finally {
    Write-Host "Cleaning up $RemoteTempDir on ${HypervHost}" -ForegroundColor Cyan
    & ssh -o RemoteCommand=none $HypervHost "powershell -NoProfile -Command `"Remove-Item -Recurse -Force '$RemoteTempDir' -ErrorAction SilentlyContinue`""
}

Write-Host "Done." -ForegroundColor Green
