#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

<#
Creates the 3 sandbox VMs (guac-1/2/3) per PLAN.md's "Hyper-V VM Settings
(Sandbox Only)" section: Generation 2, Secure Boot, 8 vCPU, 16GB fixed RAM,
no automatic checkpoints, no time-sync integration service, external
vSwitch with no VLAN tag, static + spoofed MAC.

Each VM gets the RHEL 10.2 ISO as its boot DVD, plus a second small virtual
disk labeled OEMDRV containing that node's rendered ks.cfg. Anaconda
auto-detects any attached volume labeled OEMDRV with /ks.cfg at its root
and uses it — no kernel boot args, no network, no manual console step.

Errors if any of the 3 VMs already exist — run Delete-SandboxVMs.ps1 first
to tear down before recreating.

Edit the variables below, then run: .\Create-SandboxVMs.ps1
Expects this node's .ks files sitting next to this script (same dir).
#>

$ErrorActionPreference = "Stop"

$IsoPath = 'V:\ISOs\rhel-10.2-x86_64-dvd.iso'
$VhdRoot = 'V:\Hyper-V'
$SwitchName = 'Lab'
$DiskSizeGB = 100
$KickstartDir = $PSScriptRoot

$Nodes = @("guac-1", "guac-2", "guac-3")

$existing = $Nodes | Where-Object { Get-VM -Name $_ -ErrorAction SilentlyContinue }
if ($existing) {
    throw "VM(s) already exist: $($existing -join ', ') — run Delete-SandboxVMs.ps1 first"
}

function New-OemdrvDisk {
    param(
        [Parameter(Mandatory)][string]$KickstartPath,
        [Parameter(Mandatory)][string]$VhdPath
    )

    if (-not (Test-Path $KickstartPath)) {
        throw "Kickstart file not found: $KickstartPath (render it first with kickstart/render_kickstarts.yml)"
    }

    New-VHD -Path $VhdPath -SizeBytes 128MB -Dynamic | Out-Null
    $disk = Mount-VHD -Path $VhdPath -Passthru | Get-Disk
    Initialize-Disk -Number $disk.Number -PartitionStyle MBR
    $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    Format-Volume -DriveLetter $partition.DriveLetter -FileSystem FAT -NewFileSystemLabel "OEMDRV" -Confirm:$false | Out-Null
    Copy-Item -Path $KickstartPath -Destination "$($partition.DriveLetter):\ks.cfg"
    Dismount-VHD -Path $VhdPath
}

if (-not (Test-Path $VhdRoot)) {
    New-Item -Path $VhdRoot -ItemType Directory | Out-Null
}

foreach ($name in $Nodes) {
    Write-Host "[$name] creating VM" -ForegroundColor Cyan

    $osVhd     = Join-Path $VhdRoot "$name.vhdx"
    $oemdrvVhd = Join-Path $VhdRoot "$name-oemdrv.vhdx"
    $ksFile    = Join-Path $KickstartDir "$name.ks"

    New-VHD -Path $osVhd -SizeBytes ($DiskSizeGB * 1GB) -Dynamic | Out-Null
    New-OemdrvDisk -KickstartPath $ksFile -VhdPath $oemdrvVhd

    New-VM -Name $name -Generation 2 -MemoryStartupBytes 16GB -VHDPath $osVhd -SwitchName $SwitchName | Out-Null

    Set-VMProcessor -VMName $name -Count 8
    Set-VMMemory -VMName $name -DynamicMemoryEnabled $false -StartupBytes 16GB
    Set-VM -VMName $name -AutomaticCheckpointsEnabled $false
    Disable-VMIntegrationService -VMName $name -Name "Time Synchronization"
    Set-VMFirmware -VMName $name -SecureBootTemplate MicrosoftUEFICertificateAuthority

    Add-VMDvdDrive -VMName $name -Path $IsoPath
    Add-VMHardDiskDrive -VMName $name -Path $oemdrvVhd

    $dvd = Get-VMDvdDrive -VMName $name
    Set-VMFirmware -VMName $name -FirstBootDevice $dvd

    Set-VMNetworkAdapter -VMName $name -MacAddressSpoofing On
    $mac = (Get-VMNetworkAdapter -VMName $name).MacAddress
    Set-VMNetworkAdapter -VMName $name -StaticMacAddress $mac

    Write-Host "[$name] created. Static MAC: $mac" -ForegroundColor Green
    Write-Host "[$name] add a UniFi DHCP reservation for this MAC before first boot" -ForegroundColor Green
}

Write-Host "`nDone. Review settings in Hyper-V Manager, then Start-VM each node once its UniFi reservation is in place." -ForegroundColor Cyan
