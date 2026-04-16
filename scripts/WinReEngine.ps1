[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Brand = 'Mach1 (by TAD)'
$script:VerboseMode = $false
$script:LogPath = 'X:\mach1-winre.log'
$script:MountedHives = @()
$script:Mach1Root = $null

function Write-M1Banner {
    Clear-Host
    Write-Host '+-------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '| Mach1 Recovery Engine [BETA]                                           |' -ForegroundColor Black -BackgroundColor Cyan
    Write-Host '| Offline Optimization Console                                           |' -ForegroundColor Black -BackgroundColor Cyan
    Write-Host '+-------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-M1Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'SKIP')]
        [string]$Level = 'INFO',

        [switch]$Always
    )

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$stamp] [$script:Brand] [$Level] $Message"

    $show = $Always -or $script:VerboseMode -or $Level -in @('SUCCESS', 'WARN', 'ERROR')
    if ($show) {
        $color = switch ($Level) {
            'SUCCESS' { 'Green' }
            'WARN' { 'Yellow' }
            'ERROR' { 'Red' }
            'SKIP' { 'DarkYellow' }
            default { 'Gray' }
        }

        Write-Host $line -ForegroundColor $color
    }

    try {
        Add-Content -Path $script:LogPath -Value $line
    }
    catch {
    }
}

function Update-M1Progress {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Current,

        [Parameter(Mandatory = $true)]
        [int]$Total,

        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    $percent = if ($Total -le 0) { 0 } else { [int](($Current / [double]$Total) * 100) }
    if ($percent -gt 100) {
        $percent = 100
    }

    Write-Progress -Activity "$script:Brand - WinRE Engine" -Status $Status -PercentComplete $percent
}

function Convert-ToBoolean {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    switch -Regex ($Value) {
        '^(1|true|yes|on)$' { return $true }
        default { return $false }
    }
}

function Get-WindowsDrive {
    $letters = @('C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','Y','Z','X')

    foreach ($letter in $letters) {
        $candidate = ('{0}:\Windows\System32\Config\SYSTEM' -f $letter)
        if (Test-Path -LiteralPath $candidate) {
            return ('{0}:' -f $letter)
        }
    }

    throw 'Windows partition could not be detected in WinRE.'
}

function Get-Mach1Root {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsDrive
    )

    $preferred = Join-Path -Path $WindowsDrive -ChildPath 'Mach1'
    if (Test-Path -LiteralPath $preferred) {
        return $preferred
    }

    $letters = @('C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','Y','Z','X')
    foreach ($letter in $letters) {
        $candidate = ('{0}:\Mach1' -f $letter)
        $settingsPath = Join-Path -Path $candidate -ChildPath 'Config\settings.xml'
        if (Test-Path -LiteralPath $settingsPath) {
            return $candidate
        }
    }

    throw 'Mach1 root folder was not found on any accessible partition.'
}

function Read-Mach1Settings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingsPath
    )

    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        throw "Missing settings.xml at $SettingsPath"
    }

    [xml]$xml = Get-Content -Path $SettingsPath -Raw

    return [pscustomobject]@{
        KernelTimerTweaks = Convert-ToBoolean -Value ([string]$xml.Mach1Settings.KernelTimerTweaks)
        ServiceHardening = Convert-ToBoolean -Value ([string]$xml.Mach1Settings.ServiceHardening)
        Cs2PerformancePack = Convert-ToBoolean -Value ([string]$xml.Mach1Settings.Cs2PerformancePack)
        VerboseMode = Convert-ToBoolean -Value ([string]$xml.Mach1Settings.VerboseMode)
        ReleaseTag = [string]$xml.Mach1Settings.ReleaseTag
    }
}

function Initialize-VerboseToggle {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$FromConfig
    )

    $script:VerboseMode = $FromConfig

    Write-Host ('Verbose mode from Stage 1 config: {0}' -f ($(if ($script:VerboseMode) { 'ON' } else { 'OFF' }))) -ForegroundColor Yellow
    Write-Host 'Press V within 4 seconds to toggle verbose mode.' -ForegroundColor Yellow

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 4) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::V) {
                    $script:VerboseMode = -not $script:VerboseMode
                    break
                }
            }

            Start-Sleep -Milliseconds 120
        }
    }
    catch {
    }

    Write-M1Log -Level 'INFO' -Always -Message ('Verbose mode active: {0}' -f $script:VerboseMode)
}

function Show-M1RecoveryPanel {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Settings,

        [Parameter(Mandatory = $true)]
        [string]$WindowsDrive,

        [Parameter(Mandatory = $true)]
        [string]$Mach1Root
    )

    $kernelState = if ($Settings.KernelTimerTweaks) { 'ENABLED' } else { 'DISABLED' }
    $serviceState = if ($Settings.ServiceHardening) { 'ENABLED' } else { 'DISABLED' }
    $gameState = if ($Settings.Cs2PerformancePack) { 'ENABLED (CS2)' } else { 'DISABLED' }
    $verboseState = if ($script:VerboseMode) { 'ON' } else { 'OFF' }

    Clear-Host
    Write-Host '+-------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '| Mach1 Recovery Execution Panel                                         |' -ForegroundColor Black -BackgroundColor Cyan
    Write-Host '+-------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ('| Windows Target: {0,-57}|' -f $WindowsDrive) -ForegroundColor Gray
    Write-Host ('| Mach1 Root   : {0,-57}|' -f $Mach1Root) -ForegroundColor Gray
    Write-Host ('| Release      : {0,-57}|' -f $Settings.ReleaseTag) -ForegroundColor Gray
    Write-Host '+-------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ('| Kernel/Timer Tweaks      : {0,-42}|' -f $kernelState) -ForegroundColor White
    Write-Host ('| Service Hardening        : {0,-42}|' -f $serviceState) -ForegroundColor White
    Write-Host ('| Game Optimization        : {0,-42}|' -f $gameState) -ForegroundColor White
    Write-Host ('| Verbose WinRE Output     : {0,-42}|' -f $verboseState) -ForegroundColor White
    Write-Host '+-------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '| Controls                                                                |' -ForegroundColor DarkCyan
    Write-Host '| Enter = Start now    V = Toggle Verbose    A = Abort to Recovery UI    |' -ForegroundColor DarkCyan
    Write-Host '| Auto-start in 8 seconds.                                                |' -ForegroundColor DarkCyan
    Write-Host '+-------------------------------------------------------------------------+' -ForegroundColor DarkCyan

    $deadline = (Get-Date).AddSeconds(8)

    try {
        while ((Get-Date) -lt $deadline) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Enter) {
                    return $true
                }

                if ($key.Key -eq [ConsoleKey]::A) {
                    return $false
                }

                if ($key.Key -eq [ConsoleKey]::V) {
                    $script:VerboseMode = -not $script:VerboseMode
                    $mode = if ($script:VerboseMode) { 'ON' } else { 'OFF' }
                    Write-Host ("Verbose mode toggled: {0}" -f $mode) -ForegroundColor Yellow
                }
            }

            Start-Sleep -Milliseconds 120
        }
    }
    catch {
    }

    return $true
}

function Mount-OfflineHive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$HiveFile
    )

    if (-not (Test-Path -LiteralPath $HiveFile)) {
        throw "Hive file not found: $HiveFile"
    }

    $target = "$Root\$Name"
    $output = & reg.exe load $target $HiveFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to mount hive $target from $HiveFile. Output: $($output -join ' ')"
    }

    $script:MountedHives += [pscustomobject]@{ Root = $Root; Name = $Name }
    Write-M1Log -Level 'SUCCESS' -Message "Mounted hive: $target"
}

function Unmount-OfflineHive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $target = "$Root\$Name"
    $output = & reg.exe unload $target 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-M1Log -Level 'WARN' -Message "Failed to unload hive $target. Output: $($output -join ' ')"
        return
    }

    Write-M1Log -Level 'SUCCESS' -Message "Unmounted hive: $target"
}

function Cleanup-Hives {
    for ($i = $script:MountedHives.Count - 1; $i -ge 0; $i--) {
        $entry = $script:MountedHives[$i]
        Unmount-OfflineHive -Root ([string]$entry.Root) -Name ([string]$entry.Name)
    }

    $script:MountedHives = @()
}

function Invoke-RegSetDword {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $output = & reg.exe add $Path /v $Name /t REG_DWORD /d $Value /f 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set DWORD $Path :: $Name = $Value. Output: $($output -join ' ')"
    }

    Write-M1Log -Level 'SUCCESS' -Message "[SUCCESS] $Path\\$Name = $Value"
}

function Invoke-RegSetString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $output = & reg.exe add $Path /v $Name /t REG_SZ /d $Value /f 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set REG_SZ $Path :: $Name = $Value. Output: $($output -join ' ')"
    }

    Write-M1Log -Level 'SUCCESS' -Message "[SUCCESS] $Path\\$Name = $Value"
}

function Get-OfflineOsProfile {
    $path = 'Registry::HKEY_LOCAL_MACHINE\OFFLINE_SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $item = Get-ItemProperty -Path $path -ErrorAction Stop

    $productName = [string]$item.ProductName
    $edition = [string]$item.EditionID

    return [pscustomobject]@{
        ProductName = $productName
        Edition = $edition
        IsWindows11 = ($productName -match 'Windows 11')
        IsWindows10Ltsc = (($productName -match 'Windows 10') -and (($edition -match 'LTSC|EnterpriseS|IoTEnterpriseS') -or ($productName -match 'LTSC')))
    }
}

function Invoke-KernelTimerModule {
    Write-M1Log -Level 'INFO' -Always -Message 'Applying Kernel/Timer module...'

    $cmdA = & bcdedit /set disabledynamictick yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "BCDEdit failed for disabledynamictick. Output: $($cmdA -join ' ')"
    }
    Write-M1Log -Level 'SUCCESS' -Message '[SUCCESS] bcdedit disabledynamictick yes'

    $cmdB = & bcdedit /set useplatformclock no 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "BCDEdit failed for useplatformclock. Output: $($cmdB -join ' ')"
    }
    Write-M1Log -Level 'SUCCESS' -Message '[SUCCESS] bcdedit useplatformclock no'

    $cmdC = & bcdedit /set tscsyncpolicy Enhanced 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "BCDEdit failed for tscsyncpolicy. Output: $($cmdC -join ' ')"
    }
    Write-M1Log -Level 'SUCCESS' -Message '[SUCCESS] bcdedit tscsyncpolicy Enhanced'

    Invoke-RegSetDword -Path 'HKLM\OFFLINE_SYSTEM\ControlSet001\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value '26'
    Invoke-RegSetDword -Path 'HKLM\OFFLINE_SYSTEM\ControlSet001\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff' -Value '1'
}

function Invoke-ServiceHardeningModule {
    Write-M1Log -Level 'INFO' -Always -Message 'Applying Service Hardening module...'

    $targets = @(
        @{ Name = 'SysMain'; Value = '4' },
        @{ Name = 'MapsBroker'; Value = '3' },
        @{ Name = 'DiagTrack'; Value = '4' },
        @{ Name = 'dmwappushservice'; Value = '4' },
        @{ Name = 'WerSvc'; Value = '4' }
    )

    foreach ($target in $targets) {
        $servicePath = 'HKLM\OFFLINE_SYSTEM\ControlSet001\Services\' + $target.Name
        Invoke-RegSetDword -Path $servicePath -Name 'Start' -Value $target.Value
    }

    Invoke-RegSetDword -Path 'HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value '0'
    Invoke-RegSetDword -Path 'HKLM\OFFLINE_SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'LimitDiagnosticLogCollection' -Value '0'
}

function Invoke-GameOptimizationModule {
    Write-M1Log -Level 'INFO' -Always -Message 'Applying Game Optimization module (CS2)...'

    Invoke-RegSetDword -Path 'HKLM\OFFLINE_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value '0xffffffff'

    $interfaceRoot = 'Registry::HKEY_LOCAL_MACHINE\OFFLINE_SYSTEM\ControlSet001\Services\Tcpip\Parameters\Interfaces'
    if (Test-Path -LiteralPath $interfaceRoot) {
        $interfaceKeys = Get-ChildItem -Path $interfaceRoot -ErrorAction SilentlyContinue
        foreach ($interfaceKey in @($interfaceKeys)) {
            $rawPath = 'HKLM\OFFLINE_SYSTEM\ControlSet001\Services\Tcpip\Parameters\Interfaces\' + $interfaceKey.PSChildName
            Invoke-RegSetDword -Path $rawPath -Name 'TcpAckFrequency' -Value '1'
            Invoke-RegSetDword -Path $rawPath -Name 'TCPNoDelay' -Value '1'
        }
    }
    else {
        Write-M1Log -Level 'SKIP' -Message 'No offline TCP interface keys found for Nagle tweaks.'
    }

    Invoke-RegSetDword -Path 'HKLM\OFFLINE_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions' -Name 'CpuPriorityClass' -Value '3'
    Invoke-RegSetDword -Path 'HKLM\OFFLINE_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions' -Name 'IoPriority' -Value '3'

    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'cs2.exe' -Value 'GpuPreference=2;'

    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Mouse' -Name 'MouseTrails' -Value '0'
    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0'
    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0'
    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0'
    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Mouse' -Name 'CursorShadow' -Value '0'
    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Desktop' -Name 'CursorShadow' -Value '0'
}

function Invoke-Win11SpecificGuard {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Profile
    )

    if ($Profile.IsWindows10Ltsc) {
        Write-M1Log -Level 'SKIP' -Always -Message 'W10 LTSC detected: Win11-specific appx/telemetry removals are skipped.'
        return
    }

    if (-not $Profile.IsWindows11) {
        Write-M1Log -Level 'SKIP' -Message 'System is not Windows 11. Win11-specific removals are skipped.'
        return
    }

    Write-M1Log -Level 'INFO' -Message 'Windows 11 detected. No Win11-specific removal package is selected in this beta build.'
}

function Clear-StartupTrigger {
    if ($null -eq $script:Mach1Root) {
        return
    }

    $pendingFile = Join-Path -Path $script:Mach1Root -ChildPath 'Config\patch.pending'
    if (Test-Path -LiteralPath $pendingFile) {
        Remove-Item -Path $pendingFile -Force
        Write-M1Log -Level 'SUCCESS' -Message 'Pending trigger file removed.'
    }

    & reg.exe delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' /v 'Mach1ByTad' /f 2>$null | Out-Null
    Write-M1Log -Level 'INFO' -Message 'WinRE startup trigger cleanup executed.'
}

function Reboot-BackToWindows {
    Write-M1Log -Level 'INFO' -Always -Message 'Rebooting back to live Windows...'
    & wpeutil reboot
    exit 0
}

function Abort-And-Reboot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    Write-M1Log -Level 'ERROR' -Always -Message $Reason
    Cleanup-Hives
    Clear-StartupTrigger
    Write-M1Log -Level 'WARN' -Always -Message 'Abort path triggered. Rebooting to prevent any boot-loop risk.'
    & wpeutil reboot
    exit 1
}

Write-M1Banner

$progressStep = 0
$totalSteps = 10

try {
    Update-M1Progress -Current $progressStep -Total $totalSteps -Status 'Detecting offline Windows partition'
    $windowsDrive = Get-WindowsDrive
    $progressStep++

    Update-M1Progress -Current $progressStep -Total $totalSteps -Status 'Locating Mach1 workspace'
    $script:Mach1Root = Get-Mach1Root -WindowsDrive $windowsDrive
    $progressStep++

    $script:LogPath = Join-Path -Path $script:Mach1Root -ChildPath 'Logs\mach1-winre.log'
    Write-M1Log -Level 'INFO' -Always -Message "Windows partition: $windowsDrive"
    Write-M1Log -Level 'INFO' -Always -Message "Mach1 root: $script:Mach1Root"

    $pendingFile = Join-Path -Path $script:Mach1Root -ChildPath 'Config\patch.pending'
    if (-not (Test-Path -LiteralPath $pendingFile)) {
        Write-M1Log -Level 'WARN' -Always -Message 'No pending patch trigger found. Launching default Recovery UI.'
        Start-Process -FilePath 'X:\Windows\System32\RecEnv.exe' -ErrorAction SilentlyContinue
        exit 0
    }

    $settingsPath = Join-Path -Path $script:Mach1Root -ChildPath 'Config\settings.xml'
    Update-M1Progress -Current $progressStep -Total $totalSteps -Status 'Reading Stage 1 settings'
    $settings = Read-Mach1Settings -SettingsPath $settingsPath
    $progressStep++

    Initialize-VerboseToggle -FromConfig $settings.VerboseMode
    Write-M1Log -Level 'INFO' -Always -Message "Release in scope: $($settings.ReleaseTag)"

    $continueExecution = Show-M1RecoveryPanel -Settings $settings -WindowsDrive $windowsDrive -Mach1Root $script:Mach1Root
    if (-not $continueExecution) {
        Write-M1Log -Level 'WARN' -Always -Message 'Recovery execution canceled by operator. Returning to default Recovery UI.'
        Clear-StartupTrigger
        Start-Process -FilePath 'X:\Windows\System32\RecEnv.exe' -ErrorAction SilentlyContinue
        exit 0
    }

    $offlineSystem = Join-Path -Path $windowsDrive -ChildPath 'Windows\System32\Config\SYSTEM'
    $offlineSoftware = Join-Path -Path $windowsDrive -ChildPath 'Windows\System32\Config\SOFTWARE'

    $ntUserCandidates = @(
        (Join-Path -Path $windowsDrive -ChildPath 'Users\Default\NTUSER.DAT'),
        (Join-Path -Path $windowsDrive -ChildPath 'Documents and Settings\Default User\NTUSER.DAT')
    )
    $offlineNtUser = @($ntUserCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
    if ($offlineNtUser.Count -eq 0) {
        throw 'NTUSER.DAT could not be located for offline user hive mounting.'
    }

    Update-M1Progress -Current $progressStep -Total $totalSteps -Status 'Mounting offline hives'
    Mount-OfflineHive -Root 'HKLM' -Name 'OFFLINE_SYSTEM' -HiveFile $offlineSystem
    Mount-OfflineHive -Root 'HKLM' -Name 'OFFLINE_SOFTWARE' -HiveFile $offlineSoftware
    Mount-OfflineHive -Root 'HKU' -Name 'OFFLINE_NTUSER' -HiveFile $offlineNtUser[0]
    $progressStep++

    $osProfile = Get-OfflineOsProfile
    Write-M1Log -Level 'INFO' -Always -Message "Offline OS: $($osProfile.ProductName) | Edition: $($osProfile.Edition)"

    Invoke-Win11SpecificGuard -Profile $osProfile
    $progressStep++
    Update-M1Progress -Current $progressStep -Total $totalSteps -Status 'Applying selected modules'

    if ($settings.KernelTimerTweaks) {
        Invoke-KernelTimerModule
    }
    else {
        Write-M1Log -Level 'SKIP' -Message 'Kernel/Timer module not selected.'
    }

    $progressStep++
    Update-M1Progress -Current $progressStep -Total $totalSteps -Status 'Applying service hardening'

    if ($settings.ServiceHardening) {
        Invoke-ServiceHardeningModule
    }
    else {
        Write-M1Log -Level 'SKIP' -Message 'Service Hardening module not selected.'
    }

    $progressStep++
    Update-M1Progress -Current $progressStep -Total $totalSteps -Status 'Applying game optimization (CS2)'

    if ($settings.Cs2PerformancePack) {
        Invoke-GameOptimizationModule
    }
    else {
        Write-M1Log -Level 'SKIP' -Message 'Game Optimization module (CS2) not selected.'
    }

    $progressStep++
    Update-M1Progress -Current $progressStep -Total $totalSteps -Status 'Finalizing and cleaning up'

    Cleanup-Hives
    Clear-StartupTrigger

    $progressStep = $totalSteps
    Update-M1Progress -Current $progressStep -Total $totalSteps -Status 'Completed'
    Write-M1Log -Level 'SUCCESS' -Always -Message 'All selected offline operations completed successfully.'

    Reboot-BackToWindows
}
catch {
    Abort-And-Reboot -Reason ("Critical WinRE engine failure: $($_.Exception.Message)")
}
