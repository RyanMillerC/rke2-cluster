#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

<#
Tears down the 3 sandbox VMs (pico-1/2/3): stops each if running, removes
the VM, then deletes its OS and OEMDRV VHDs. A node that doesn't exist is
skipped with a warning, not an error — safe to run even if creation only
got partway through.

Edit the variable below, then run: .\Delete-SandboxVMs.ps1
#>

$ErrorActionPreference = "Stop"

$VhdRoot = 'V:\Hyper-V'

$Nodes = @("pico-1", "pico-2", "pico-3")

foreach ($name in $Nodes) {
    $vm = Get-VM -Name $name -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Host "[$name] does not exist, skipping" -ForegroundColor Yellow
        continue
    }

    if ($vm.State -ne 'Off') {
        Write-Host "[$name] stopping" -ForegroundColor Cyan
        Stop-VM -Name $name -TurnOff -Force
    }

    Write-Host "[$name] removing VM" -ForegroundColor Cyan
    Remove-VM -Name $name -Force

    foreach ($suffix in @("", "-oemdrv")) {
        $vhd = Join-Path $VhdRoot "$name$suffix.vhdx"
        if (Test-Path $vhd) {
            Remove-Item -Path $vhd -Force
        }
    }

    Write-Host "[$name] deleted" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
