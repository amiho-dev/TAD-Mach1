[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Brand = 'Mach1 (by TAD)'
$script:CurrentRelease = 'M1.0415.001.BF'

$script:Paths = [ordered]@{
    Root = 'C:\Mach1'
    ConfigDirectory = 'C:\Mach1\Config'
    LogDirectory = 'C:\Mach1\Logs'
    WinReDirectory = 'C:\Mach1\WinRE'
    WinReMountDirectory = 'C:\Mach1\WinRE\Mount'
    WinReWorkDirectory = 'C:\Mach1\WinRE\Work'
    SettingsXmlPath = 'C:\Mach1\Config\settings.xml'
    PendingFlagPath = 'C:\Mach1\Config\patch.pending'
    OrchestratorLogPath = 'C:\Mach1\Logs\mach1-orchestrator.log'
    WinReLogPath = 'C:\Mach1\Logs\mach1-winre.log'
    InstalledEngineScriptPath = 'C:\Mach1\WinRE\WinReEngine.ps1'
}

$script:Ui = [ordered]@{
    KernelTimerTweaks = $false
    ServiceHardening = $false
    Cs2PerformancePack = $false
    VerboseMode = $false
    BackupToggleConfirmed = $false
    BackupCompleted = $false
    LastSavedUtc = ''
    Status = 'Starting...'
}

function New-M1SettingsObject {
    param(
        [bool]$KernelTimerTweaks = $false,
        [bool]$ServiceHardening = $false,
        [bool]$Cs2PerformancePack = $false,
        [bool]$VerboseMode = $false,
        [bool]$BackupToggleConfirmed = $false,
        [bool]$BackupCompleted = $false,
        [string]$ReleaseTag = $script:CurrentRelease,
        [string]$SavedUtc = ''
    )

    if ([string]::IsNullOrWhiteSpace($SavedUtc)) {
        $SavedUtc = [DateTime]::UtcNow.ToString('O')
    }

    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        $ReleaseTag = $script:CurrentRelease
    }

    return [pscustomobject]@{
        KernelTimerTweaks = $KernelTimerTweaks
        ServiceHardening = $ServiceHardening
        Cs2PerformancePack = $Cs2PerformancePack
        VerboseMode = $VerboseMode
        BackupToggleConfirmed = $BackupToggleConfirmed
        BackupCompleted = $BackupCompleted
        ReleaseTag = $ReleaseTag
        SavedUtc = $SavedUtc
    }
}

function Convert-ToM1Boolean {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    switch -Regex ($Value.Trim().ToLowerInvariant()) {
        '^(1|true|yes|on)$' { return $true }
        default { return $false }
    }
}

function Convert-M1BooleanToXml {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Value
    )

    return $Value.ToString().ToLowerInvariant()
}

function Ensure-M1Layout {
    foreach ($path in @(
        $script:Paths.Root,
        $script:Paths.ConfigDirectory,
        $script:Paths.LogDirectory,
        $script:Paths.WinReDirectory,
        $script:Paths.WinReMountDirectory,
        $script:Paths.WinReWorkDirectory
    )) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

function Write-M1Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    Ensure-M1Layout

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$stamp] [$script:Brand] [$Level] $Message"

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'Gray' }
    }

    Write-Host $line -ForegroundColor $color

    try {
        Add-Content -Path $script:Paths.OrchestratorLogPath -Value $line -Encoding UTF8
    }
    catch {
    }
}

function Set-M1Status {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $script:Ui.Status = $Message
    Write-M1Log -Message $Message -Level $Level
}

function Test-M1Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-M1Administrator {
    if (Test-M1Administrator) {
        return
    }

    if (-not $PSCommandPath) {
        throw 'Mach1 requires Administrator privileges to start.'
    }

    $hostExe = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
    if (-not (Test-Path -LiteralPath $hostExe)) {
        try {
            $hostExe = (Get-Process -Id $PID).Path
        }
        catch {
            $hostExe = 'powershell.exe'
        }
    }

    Write-Host 'Mach1 requires Administrator privileges. Relaunching elevated...' -ForegroundColor Yellow

    try {
        Start-Process -FilePath $hostExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) -Verb RunAs | Out-Null
        exit 0
    }
    catch {
        throw 'Mach1 requires Administrator privileges to open. Elevation was canceled or unavailable.'
    }
}

function Get-M1EngineSourceCandidates {
    $candidates = @(
        (Join-Path -Path $PSScriptRoot -ChildPath 'scripts\WinReEngine.ps1'),
        (Join-Path -Path $PSScriptRoot -ChildPath 'WinReEngine.ps1'),
        (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'scripts\WinReEngine.ps1')
    )

    $resolved = @()
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            if ($resolved -notcontains $candidate) {
                $resolved += $candidate
            }
        }
    }

    return $resolved
}

function Ensure-M1EngineScriptInstalled {
    $sourceCandidates = Get-M1EngineSourceCandidates

    if ($sourceCandidates.Count -gt 0) {
        Copy-Item -LiteralPath $sourceCandidates[0] -Destination $script:Paths.InstalledEngineScriptPath -Force
        Write-M1Log -Level 'SUCCESS' -Message "WinRE engine script installed from $($sourceCandidates[0])."
        return
    }

    if (Test-Path -LiteralPath $script:Paths.InstalledEngineScriptPath) {
        Write-M1Log -Level 'INFO' -Message 'Using existing installed WinRE engine script from C:\Mach1\WinRE.'
        return
    }

    throw 'WinReEngine.ps1 was not found next to this launcher and no installed copy exists in C:\Mach1\WinRE.'
}

function Write-M1BetaNotice {
    $betaInfoPath = Join-Path -Path $script:Paths.ConfigDirectory -ChildPath 'beta-info.txt'
    $text = @(
        'Mach1 (by TAD)',
        'BETA - Use at your own risk.',
        'This build prepares a reboot-to-WinRE patching flow.',
        'Mandatory backup is required before enabling patch mode.',
        ('Release: {0}' -f $script:CurrentRelease)
    )

    Set-Content -Path $betaInfoPath -Value $text -Encoding ASCII
}

function Load-M1SettingsOrDefault {
    if (-not (Test-Path -LiteralPath $script:Paths.SettingsXmlPath)) {
        return New-M1SettingsObject
    }

    try {
        [xml]$xml = Get-Content -Path $script:Paths.SettingsXmlPath -Raw
        $root = $xml.Mach1Settings

        if ($null -eq $root) {
            return New-M1SettingsObject
        }

        $settingsArgs = @{
            KernelTimerTweaks = (Convert-ToM1Boolean -Value ([string]$root.KernelTimerTweaks))
            ServiceHardening = (Convert-ToM1Boolean -Value ([string]$root.ServiceHardening))
            Cs2PerformancePack = (Convert-ToM1Boolean -Value ([string]$root.Cs2PerformancePack))
            VerboseMode = (Convert-ToM1Boolean -Value ([string]$root.VerboseMode))
            BackupToggleConfirmed = (Convert-ToM1Boolean -Value ([string]$root.BackupToggleConfirmed))
            BackupCompleted = (Convert-ToM1Boolean -Value ([string]$root.BackupCompleted))
            ReleaseTag = ([string]$root.ReleaseTag)
            SavedUtc = ([string]$root.SavedUtc)
        }

        return New-M1SettingsObject @settingsArgs
    }
    catch {
        Write-M1Log -Level 'WARN' -Message "Could not load settings.xml, using defaults. $($_.Exception.Message)"
        return New-M1SettingsObject
    }
}

function Save-M1Settings {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Settings
    )

    $Settings.ReleaseTag = if ([string]::IsNullOrWhiteSpace([string]$Settings.ReleaseTag)) { $script:CurrentRelease } else { [string]$Settings.ReleaseTag }
    $Settings.SavedUtc = [DateTime]::UtcNow.ToString('O')

    $kernelTimer = Convert-M1BooleanToXml -Value ([bool]$Settings.KernelTimerTweaks)
    $serviceHardening = Convert-M1BooleanToXml -Value ([bool]$Settings.ServiceHardening)
    $cs2Pack = Convert-M1BooleanToXml -Value ([bool]$Settings.Cs2PerformancePack)
    $verboseMode = Convert-M1BooleanToXml -Value ([bool]$Settings.VerboseMode)
    $backupToggle = Convert-M1BooleanToXml -Value ([bool]$Settings.BackupToggleConfirmed)
    $backupCompleted = Convert-M1BooleanToXml -Value ([bool]$Settings.BackupCompleted)

    $xmlText = @"
<?xml version="1.0" encoding="utf-8"?>
<Mach1Settings>
  <KernelTimerTweaks>$kernelTimer</KernelTimerTweaks>
  <ServiceHardening>$serviceHardening</ServiceHardening>
  <Cs2PerformancePack>$cs2Pack</Cs2PerformancePack>
  <VerboseMode>$verboseMode</VerboseMode>
  <BackupToggleConfirmed>$backupToggle</BackupToggleConfirmed>
  <BackupCompleted>$backupCompleted</BackupCompleted>
  <ReleaseTag>$($Settings.ReleaseTag)</ReleaseTag>
  <SavedUtc>$($Settings.SavedUtc)</SavedUtc>
</Mach1Settings>
"@

    Set-Content -Path $script:Paths.SettingsXmlPath -Value $xmlText -Encoding UTF8
    $script:Ui.LastSavedUtc = [string]$Settings.SavedUtc

    Set-M1Status -Level 'SUCCESS' -Message 'Selection saved to settings.xml.'
}

function Apply-M1SettingsToUi {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Settings
    )

    $script:Ui.KernelTimerTweaks = [bool]$Settings.KernelTimerTweaks
    $script:Ui.ServiceHardening = [bool]$Settings.ServiceHardening
    $script:Ui.Cs2PerformancePack = [bool]$Settings.Cs2PerformancePack
    $script:Ui.VerboseMode = [bool]$Settings.VerboseMode
    $script:Ui.BackupToggleConfirmed = [bool]$Settings.BackupToggleConfirmed
    $script:Ui.BackupCompleted = [bool]$Settings.BackupCompleted
    $script:Ui.LastSavedUtc = [string]$Settings.SavedUtc
}

function New-M1SettingsFromUi {
    $settingsArgs = @{
        KernelTimerTweaks = $script:Ui.KernelTimerTweaks
        ServiceHardening = $script:Ui.ServiceHardening
        Cs2PerformancePack = $script:Ui.Cs2PerformancePack
        VerboseMode = $script:Ui.VerboseMode
        BackupToggleConfirmed = $script:Ui.BackupToggleConfirmed
        BackupCompleted = $script:Ui.BackupCompleted
        ReleaseTag = $script:CurrentRelease
    }

    return New-M1SettingsObject @settingsArgs
}

function Get-M1OsLabel {
    try {
        $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        return ('{0} | Build {1}' -f [string]$cv.ProductName, [string]$cv.CurrentBuildNumber)
    }
    catch {
        return [Environment]::OSVersion.VersionString
    }
}

function Get-M1PowerShellExe {
    $candidate = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    return 'powershell.exe'
}

function Invoke-M1CreateBackup {
    Set-M1Status -Message 'Creating System Restore Point...' -Level 'INFO'

    $scriptPath = Join-Path -Path $script:Paths.WinReWorkDirectory -ChildPath 'CreateBackup.ps1'
    $scriptContent = @(
        "$ErrorActionPreference = 'Stop'",
        "Enable-ComputerRestore -Drive ($env:SystemDrive + '\\') -ErrorAction SilentlyContinue | Out-Null",
        "Checkpoint-Computer -Description 'Mach1 (by TAD) BETA Backup' -RestorePointType 'MODIFY_SETTINGS' | Out-Null"
    )

    Set-Content -Path $scriptPath -Value $scriptContent -Encoding ASCII

    $backupHost = Get-M1PowerShellExe
    $output = & $backupHost -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1

    if ($LASTEXITCODE -eq 0) {
        $script:Ui.BackupCompleted = $true
        Set-M1Status -Level 'SUCCESS' -Message 'Backup completed. You can now arm reboot-to-patch.'
        return $true
    }

    $script:Ui.BackupCompleted = $false
    Write-M1Log -Level 'ERROR' -Message ("System Restore Point failed. Output: {0}" -f (($output | Out-String).Trim()))
    Set-M1Status -Level 'ERROR' -Message 'Backup failed. Patch mode stays blocked.'
    return $false
}

function Test-M1AnyPackSelected {
    return $script:Ui.KernelTimerTweaks -or $script:Ui.ServiceHardening -or $script:Ui.Cs2PerformancePack
}

function Get-M1Readiness {
    $anyPack = Test-M1AnyPackSelected
    $backupToggle = [bool]$script:Ui.BackupToggleConfirmed
    $backupDone = [bool]$script:Ui.BackupCompleted

    $reason = ''
    if (-not $anyPack) {
        $reason = 'Select at least one optimization pack.'
    }
    elseif (-not $backupToggle) {
        $reason = 'Mandatory BETA backup toggle is not confirmed.'
    }
    elseif (-not $backupDone) {
        $reason = 'Create Backup must complete successfully before patching.'
    }

    return [pscustomobject]@{
        AnyPackSelected = $anyPack
        BackupToggleConfirmed = $backupToggle
        BackupCompleted = $backupDone
        Ready = ($anyPack -and $backupToggle -and $backupDone)
        Reason = $reason
    }
}

function Arm-M1PendingPatchTrigger {
    $content = '{0}|{1}|{2}' -f $script:Brand, ([DateTime]::UtcNow.ToString('O')), $script:CurrentRelease
    Set-Content -Path $script:Paths.PendingFlagPath -Value $content -Encoding ASCII
    Write-M1Log -Level 'SUCCESS' -Message 'Pending patch trigger created.'
}

function Clear-M1PendingPatchTrigger {
    if (Test-Path -LiteralPath $script:Paths.PendingFlagPath) {
        Remove-Item -Path $script:Paths.PendingFlagPath -Force
        Write-M1Log -Level 'INFO' -Message 'Pending patch trigger cleared.'
    }
}

function Resolve-M1WinReWimPath {
    $defaultPath = 'C:\Windows\System32\Recovery\Winre.wim'
    if (Test-Path -LiteralPath $defaultPath) {
        return $defaultPath
    }

    $infoOutput = & reagentc.exe /info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("reagentc /info failed: {0}" -f (($infoOutput | Out-String).Trim()))
    }

    $text = ($infoOutput | Out-String)
    $match = [regex]::Match($text, 'Windows RE location\s*:\s*(?<loc>.+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        throw 'WinRE image (Winre.wim) could not be resolved from reagentc output.'
    }

    $location = $match.Groups['loc'].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($location)) {
        throw 'WinRE location was empty in reagentc output.'
    }

    $candidate = if ($location.ToLowerInvariant().EndsWith('winre.wim')) {
        $location
    }
    else {
        "$location\Winre.wim"
    }

    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    throw ("WinRE image path was resolved but not found: {0}" -f $candidate)
}

function Get-M1WinPeshlIniContent {
    return @(
        '[LaunchApps]',
        '%SYSTEMDRIVE%\Windows\System32\wpeinit.exe',
        '%SYSTEMDRIVE%\Windows\System32\WindowsPowerShell\v1.0\powershell.exe,-NoProfile -ExecutionPolicy Bypass -File X:\Windows\System32\Mach1\WinReEngine.ps1'
    )
}

function Inject-M1WinReStartup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WimPath
    )

    $mountDir = $script:Paths.WinReMountDirectory

    if (-not (Test-Path -LiteralPath $mountDir)) {
        New-Item -Path $mountDir -ItemType Directory -Force | Out-Null
    }

    & dism.exe '/Unmount-Image' "/MountDir:$mountDir" '/Discard' 2>&1 | Out-Null

    $mounted = $false

    try {
        $mountOutput = & dism.exe '/Mount-Image' "/ImageFile:$WimPath" '/Index:1' "/MountDir:$mountDir" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ("DISM mount failed: {0}" -f (($mountOutput | Out-String).Trim()))
        }

        $mounted = $true

        $targetEngineDirectory = Join-Path -Path $mountDir -ChildPath 'Windows\System32\Mach1'
        if (-not (Test-Path -LiteralPath $targetEngineDirectory)) {
            New-Item -Path $targetEngineDirectory -ItemType Directory -Force | Out-Null
        }

        $targetEnginePath = Join-Path -Path $targetEngineDirectory -ChildPath 'WinReEngine.ps1'
        Copy-Item -LiteralPath $script:Paths.InstalledEngineScriptPath -Destination $targetEnginePath -Force

        $winpeshlPath = Join-Path -Path $mountDir -ChildPath 'Windows\System32\winpeshl.ini'
        Set-Content -Path $winpeshlPath -Value (Get-M1WinPeshlIniContent) -Encoding ASCII

        $unmountOutput = & dism.exe '/Unmount-Image' "/MountDir:$mountDir" '/Commit' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ("DISM unmount commit failed: {0}" -f (($unmountOutput | Out-String).Trim()))
        }

        $mounted = $false
        Write-M1Log -Level 'SUCCESS' -Message 'WinRE startup script injection completed using winpeshl.ini.'
    }
    catch {
        if ($mounted) {
            & dism.exe '/Unmount-Image' "/MountDir:$mountDir" '/Discard' 2>&1 | Out-Null
        }

        throw
    }
}

function Prepare-M1PatchBoot {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Settings
    )

    try {
        Write-Progress -Activity "$script:Brand - Stage 1" -Status 'Verifying WinRE engine script' -PercentComplete 5
        Ensure-M1EngineScriptInstalled

        Write-Progress -Activity "$script:Brand - Stage 1" -Status 'Arming pending patch trigger' -PercentComplete 20
        Arm-M1PendingPatchTrigger

        Write-Progress -Activity "$script:Brand - Stage 1" -Status 'Resolving Winre.wim path' -PercentComplete 35
        $wimPath = Resolve-M1WinReWimPath

        Write-Progress -Activity "$script:Brand - Stage 1" -Status 'Injecting WinRE startup command' -PercentComplete 60
        Inject-M1WinReStartup -WimPath $wimPath

        Write-Progress -Activity "$script:Brand - Stage 1" -Status 'Arming one-time WinRE boot' -PercentComplete 85
        $boottoreOutput = & reagentc.exe /boottore 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-M1Log -Level 'ERROR' -Message ("reagentc /boottore failed: {0}" -f (($boottoreOutput | Out-String).Trim()))
            Clear-M1PendingPatchTrigger
            return [pscustomobject]@{ Success = $false; Message = 'Could not arm WinRE one-time boot.' }
        }

        Write-M1Log -Level 'SUCCESS' -Message ("Patch flow armed for release {0}." -f [string]$Settings.ReleaseTag)
        return [pscustomobject]@{ Success = $true; Message = 'WinRE patch flow armed. Reboot will enter recovery patch stage.' }
    }
    catch {
        Clear-M1PendingPatchTrigger
        Write-M1Log -Level 'ERROR' -Message ("WinRE preparation failed: {0}" -f $_.Exception.Message)
        return [pscustomobject]@{ Success = $false; Message = $_.Exception.Message }
    }
    finally {
        Write-Progress -Activity "$script:Brand - Stage 1" -Completed
    }
}

function Invoke-M1RebootNow {
    $rebootOutput = & shutdown.exe /r /t 0 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-M1Log -Level 'ERROR' -Message ("shutdown.exe failed: {0}" -f (($rebootOutput | Out-String).Trim()))
        return [pscustomobject]@{ Success = $false; Message = 'Windows reboot command failed.' }
    }

    return [pscustomobject]@{ Success = $true; Message = 'Reboot command submitted.' }
}

function Get-M1BadgeText {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    if ($Enabled) {
        return 'ON '
    }

    return 'OFF'
}

function Write-M1ToggleLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    Write-Host ("  {0}) {1,-60}" -f $Key, $Label) -NoNewline

    if ($Enabled) {
        Write-Host ("[{0}]" -f (Get-M1BadgeText -Enabled $true)) -ForegroundColor Black -BackgroundColor Green
    }
    else {
        Write-Host ("[{0}]" -f (Get-M1BadgeText -Enabled $false)) -ForegroundColor Black -BackgroundColor DarkGray
    }
}

function Write-M1CheckLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [bool]$Pass
    )

    Write-Host ("  - {0,-48}" -f $Label) -NoNewline

    if ($Pass) {
        Write-Host '[PASS]' -ForegroundColor Green
    }
    else {
        Write-Host '[FAIL]' -ForegroundColor Red
    }
}

function Show-M1Dashboard {
    $readiness = Get-M1Readiness

    Clear-Host
    Write-Host '+-------------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '| Mach1 Recovery Orchestrator                                                  |' -ForegroundColor Black -BackgroundColor Cyan
    Write-Host '+-------------------------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host (" Release : {0}" -f $script:CurrentRelease) -ForegroundColor White
    Write-Host (" Host    : {0}" -f (Get-M1OsLabel)) -ForegroundColor Gray
    Write-Host (" Log File: {0}" -f $script:Paths.OrchestratorLogPath) -ForegroundColor DarkGray

    if (-not [string]::IsNullOrWhiteSpace($script:Ui.LastSavedUtc)) {
        Write-Host (" Saved UTC: {0}" -f $script:Ui.LastSavedUtc) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host ' BETA SAFETY' -ForegroundColor Yellow
    Write-Host '  BETA - Use at your own risk. Backup is mandatory before patch mode.' -ForegroundColor Yellow

    Write-Host ''
    Write-Host ' OPTIMIZATION MODULES' -ForegroundColor Cyan
    Write-M1ToggleLine -Key '1' -Label 'Kernel/Timer Tweaks (BCDEDIT + scheduler)' -Enabled $script:Ui.KernelTimerTweaks
    Write-M1ToggleLine -Key '2' -Label 'Service Hardening (W10 LTSC optimized)' -Enabled $script:Ui.ServiceHardening

    Write-Host ''
    Write-Host ' GAME OPTIMIZATION' -ForegroundColor Cyan
    Write-M1ToggleLine -Key '3' -Label 'Game Optimization (CS2)' -Enabled $script:Ui.Cs2PerformancePack

    Write-Host ''
    Write-Host ' RECOVERY OPTIONS' -ForegroundColor Cyan
    Write-M1ToggleLine -Key '4' -Label 'Verbose WinRE output toggle' -Enabled $script:Ui.VerboseMode

    Write-Host ''
    Write-Host ' SAFETY GATE' -ForegroundColor Magenta
    Write-M1ToggleLine -Key '5' -Label 'I confirm BETA risk and require Create Backup before patching' -Enabled $script:Ui.BackupToggleConfirmed

    Write-Host ''
    Write-Host ' ACTIONS' -ForegroundColor Cyan
    Write-Host '  6) Create Backup (Mandatory)'
    Write-Host '  7) Save Selection Only'
    Write-Host '  8) Reboot To Patch'
    Write-Host '  R) Reload settings.xml from disk'
    Write-Host '  Q) Exit'

    Write-Host ''
    Write-Host ' PATCH READINESS CHECK' -ForegroundColor Cyan
    Write-M1CheckLine -Label 'At least one optimization pack selected' -Pass $readiness.AnyPackSelected
    Write-M1CheckLine -Label 'BETA risk toggle confirmed' -Pass $readiness.BackupToggleConfirmed
    Write-M1CheckLine -Label 'Mandatory backup completed' -Pass $readiness.BackupCompleted

    Write-Host ''
    Write-Host ' STATUS' -ForegroundColor Cyan
    $statusColor = if ($readiness.Ready) { 'Green' } else { 'Yellow' }
    Write-Host ("  {0}" -f $script:Ui.Status) -ForegroundColor $statusColor

    if (-not $readiness.Ready -and -not [string]::IsNullOrWhiteSpace($readiness.Reason)) {
        Write-Host ("  Next gate: {0}" -f $readiness.Reason) -ForegroundColor Yellow
    }

    Write-Host ''
}

function Invoke-M1PatchFlow {
    $readiness = Get-M1Readiness
    if (-not $readiness.Ready) {
        Set-M1Status -Level 'WARN' -Message $readiness.Reason
        return
    }

    try {
        $settings = New-M1SettingsFromUi
        Save-M1Settings -Settings $settings

        Set-M1Status -Level 'INFO' -Message 'Saving configuration and preparing WinRE image...'
        $prep = Prepare-M1PatchBoot -Settings $settings

        if (-not $prep.Success) {
            Set-M1Status -Level 'ERROR' -Message ("Patch preparation failed: {0}" -f [string]$prep.Message)
            return
        }

        Set-M1Status -Level 'SUCCESS' -Message 'WinRE patch flow armed. Awaiting reboot confirmation.'

        $answer = Read-Host 'Mach1 is armed for Recovery patching. Reboot immediately now? (Y/N)'
        if ($answer -notmatch '^(y|yes)$') {
            Set-M1Status -Level 'WARN' -Message 'Reboot deferred by user. Trigger remains armed for next reboot.'
            return
        }

        $reboot = Invoke-M1RebootNow
        if (-not $reboot.Success) {
            Set-M1Status -Level 'ERROR' -Message ("Reboot command failed: {0}" -f [string]$reboot.Message)
        }
    }
    catch {
        Set-M1Status -Level 'ERROR' -Message ("Unexpected failure: {0}" -f $_.Exception.Message)
    }
}

function Initialize-M1Runtime {
    Ensure-M1Layout
    Ensure-M1EngineScriptInstalled
    Write-M1BetaNotice

    $loaded = Load-M1SettingsOrDefault
    Apply-M1SettingsToUi -Settings $loaded

    Set-M1Status -Level 'INFO' -Message 'Ready. Configure packs and run Create Backup before reboot-to-patch.'
}

function Start-M1NativeOrchestrator {
    if ([Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Mach1 supports Windows only.'
    }

    Ensure-M1Administrator

    try {
        Initialize-M1Runtime
    }
    catch {
        Set-M1Status -Level 'ERROR' -Message ("Initialization failed: {0}" -f $_.Exception.Message)
    }

    while ($true) {
        Show-M1Dashboard
        $choiceRaw = Read-Host 'Select an option'

        if ([string]::IsNullOrWhiteSpace($choiceRaw)) {
            continue
        }

        $choice = $choiceRaw.Trim().ToUpperInvariant()

        switch ($choice) {
            '1' {
                $script:Ui.KernelTimerTweaks = -not $script:Ui.KernelTimerTweaks
                Set-M1Status -Message ("Kernel/Timer Tweaks: {0}" -f (Get-M1BadgeText -Enabled $script:Ui.KernelTimerTweaks))
            }
            '2' {
                $script:Ui.ServiceHardening = -not $script:Ui.ServiceHardening
                Set-M1Status -Message ("Service Hardening: {0}" -f (Get-M1BadgeText -Enabled $script:Ui.ServiceHardening))
            }
            '3' {
                $script:Ui.Cs2PerformancePack = -not $script:Ui.Cs2PerformancePack
                Set-M1Status -Message ("Game Optimization (CS2): {0}" -f (Get-M1BadgeText -Enabled $script:Ui.Cs2PerformancePack))
            }
            '4' {
                $script:Ui.VerboseMode = -not $script:Ui.VerboseMode
                Set-M1Status -Message ("Verbose WinRE output: {0}" -f (Get-M1BadgeText -Enabled $script:Ui.VerboseMode))
            }
            '5' {
                $script:Ui.BackupToggleConfirmed = -not $script:Ui.BackupToggleConfirmed
                Set-M1Status -Message ("BETA risk acknowledgment: {0}" -f (Get-M1BadgeText -Enabled $script:Ui.BackupToggleConfirmed))
            }
            '6' {
                try {
                    [void](Invoke-M1CreateBackup)
                }
                catch {
                    Set-M1Status -Level 'ERROR' -Message ("Backup exception: {0}" -f $_.Exception.Message)
                }
            }
            '7' {
                try {
                    Save-M1Settings -Settings (New-M1SettingsFromUi)
                }
                catch {
                    Set-M1Status -Level 'ERROR' -Message ("Saving config failed: {0}" -f $_.Exception.Message)
                }
            }
            '8' {
                Invoke-M1PatchFlow
            }
            'R' {
                try {
                    Apply-M1SettingsToUi -Settings (Load-M1SettingsOrDefault)
                    Set-M1Status -Level 'SUCCESS' -Message 'Settings reloaded from settings.xml.'
                }
                catch {
                    Set-M1Status -Level 'ERROR' -Message ("Reload failed: {0}" -f $_.Exception.Message)
                }
            }
            'Q' {
                Set-M1Status -Message 'Exiting Mach1.'
                break
            }
            default {
                Set-M1Status -Level 'WARN' -Message ("Invalid selection: {0}" -f $choiceRaw)
            }
        }
    }
}

Start-M1NativeOrchestrator
