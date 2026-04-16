[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Brand = 'Mach1 (by TAD)'
$script:VerboseMode = $false
$script:LogPath = 'X:\mach1-winre.log'
$script:MountedHives = @()
$script:Mach1Root = $null
$script:UiEnabled = $false
$script:UiForm = $null
$script:UiLblStatus = $null
$script:UiLblCurrent = $null
$script:UiLblEta = $null
$script:UiLblHost = $null
$script:UiLblProfile = $null
$script:UiBarTotal = $null
$script:UiBarCurrent = $null
$script:StartTime = Get-Date

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

function Try-InitializeRecoveryUi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogoPath
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Mach1 Recovery Engine'
        $form.Size = New-Object System.Drawing.Size(780, 420)
        $form.StartPosition = 'CenterScreen'
        $form.FormBorderStyle = 'FixedSingle'
        $form.MaximizeBox = $false
        $form.BackColor = [System.Drawing.Color]::FromArgb(238, 242, 247)

        $logo = New-Object System.Windows.Forms.PictureBox
        $logo.Location = New-Object System.Drawing.Point(18, 14)
        $logo.Size = New-Object System.Drawing.Size(56, 56)
        $logo.SizeMode = 'Zoom'
        if (Test-Path -LiteralPath $LogoPath) {
            $logo.Image = [System.Drawing.Image]::FromFile($LogoPath)
        }

        $title = New-Object System.Windows.Forms.Label
        $title.Location = New-Object System.Drawing.Point(86, 16)
        $title.Size = New-Object System.Drawing.Size(620, 26)
        $title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
        $title.Text = 'Mach1 Recovery Environment'

        $subTitle = New-Object System.Windows.Forms.Label
        $subTitle.Location = New-Object System.Drawing.Point(88, 44)
        $subTitle.Size = New-Object System.Drawing.Size(640, 22)
        $subTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $subTitle.ForeColor = [System.Drawing.Color]::FromArgb(70, 84, 102)
        $subTitle.Text = 'Offline execution is now processing your selected deployment profile'

        $host = New-Object System.Windows.Forms.Label
        $host.Location = New-Object System.Drawing.Point(20, 88)
        $host.Size = New-Object System.Drawing.Size(730, 20)
        $host.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $host.Text = 'Host: Detection pending'

        $profile = New-Object System.Windows.Forms.Label
        $profile.Location = New-Object System.Drawing.Point(20, 110)
        $profile.Size = New-Object System.Drawing.Size(730, 20)
        $profile.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $profile.Text = 'Profile: Pending'

        $status = New-Object System.Windows.Forms.Label
        $status.Location = New-Object System.Drawing.Point(20, 144)
        $status.Size = New-Object System.Drawing.Size(730, 22)
        $status.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        $status.Text = 'Status: Starting'

        $current = New-Object System.Windows.Forms.Label
        $current.Location = New-Object System.Drawing.Point(20, 172)
        $current.Size = New-Object System.Drawing.Size(730, 20)
        $current.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $current.Text = 'Current step: Starting'

        $barTotal = New-Object System.Windows.Forms.ProgressBar
        $barTotal.Location = New-Object System.Drawing.Point(20, 202)
        $barTotal.Size = New-Object System.Drawing.Size(730, 22)
        $barTotal.Minimum = 0
        $barTotal.Maximum = 100

        $barCurrent = New-Object System.Windows.Forms.ProgressBar
        $barCurrent.Location = New-Object System.Drawing.Point(20, 240)
        $barCurrent.Size = New-Object System.Drawing.Size(730, 20)
        $barCurrent.Minimum = 0
        $barCurrent.Maximum = 100

        $eta = New-Object System.Windows.Forms.Label
        $eta.Location = New-Object System.Drawing.Point(20, 272)
        $eta.Size = New-Object System.Drawing.Size(730, 20)
        $eta.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $eta.Text = 'ETA: Calculating'

        $note = New-Object System.Windows.Forms.Label
        $note.Location = New-Object System.Drawing.Point(20, 308)
        $note.Size = New-Object System.Drawing.Size(730, 42)
        $note.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $note.ForeColor = [System.Drawing.Color]::FromArgb(82, 95, 112)
        $note.Text = 'Do not power off this machine while recovery execution is running.'

        $form.Controls.AddRange(@($logo, $title, $subTitle, $host, $profile, $status, $current, $barTotal, $barCurrent, $eta, $note))
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()

        $script:UiForm = $form
        $script:UiLblStatus = $status
        $script:UiLblCurrent = $current
        $script:UiLblEta = $eta
        $script:UiLblHost = $host
        $script:UiLblProfile = $profile
        $script:UiBarTotal = $barTotal
        $script:UiBarCurrent = $barCurrent
        $script:UiEnabled = $true
    }
    catch {
        $script:UiEnabled = $false
        Write-M1Log -Level 'WARN' -Always -Message "WinForms UI unavailable in this recovery session: $($_.Exception.Message)"
    }
}

function Set-RecoveryUiMeta {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host,

        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    if (-not $script:UiEnabled) {
        return
    }

    $script:UiLblHost.Text = "Host: $Host"
    $script:UiLblProfile.Text = "Profile: $Profile"
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-RecoveryUiProgress {
    param(
        [Parameter(Mandatory = $true)]
        [int]$TotalPercent,

        [Parameter(Mandatory = $true)]
        [int]$CurrentPercent,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$CurrentStep
    )

    $totalSafe = [Math]::Max(0, [Math]::Min(100, $TotalPercent))
    $currentSafe = [Math]::Max(0, [Math]::Min(100, $CurrentPercent))

    if ($script:UiEnabled) {
        $script:UiBarTotal.Value = $totalSafe
        $script:UiBarCurrent.Value = $currentSafe
        $script:UiLblStatus.Text = "Status: $Status"
        $script:UiLblCurrent.Text = "Current step: $CurrentStep"

        $elapsed = (Get-Date) - $script:StartTime
        if ($totalSafe -gt 0) {
            $totalSeconds = $elapsed.TotalSeconds / ($totalSafe / 100.0)
            $remaining = [TimeSpan]::FromSeconds([Math]::Max(0, $totalSeconds - $elapsed.TotalSeconds))
            $script:UiLblEta.Text = ('ETA: {0:mm\\:ss}' -f $remaining)
        }
        else {
            $script:UiLblEta.Text = 'ETA: Calculating'
        }

        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Close-RecoveryUi {
    if (-not $script:UiEnabled) {
        return
    }

    try {
        $script:UiForm.Close()
    }
    catch {
    }
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
        SessionId = [string]$xml.Mach1Settings.SessionId
        OptimizationProfile = [string]$xml.Mach1Settings.OptimizationProfile
        KernelTimerTweaks = Convert-ToBoolean -Value ([string]$xml.Mach1Settings.KernelTimerTweaks)
        ServiceHardening = Convert-ToBoolean -Value ([string]$xml.Mach1Settings.ServiceHardening)
        Cs2PerformancePack = Convert-ToBoolean -Value ([string]$xml.Mach1Settings.Cs2PerformancePack)
        VerboseMode = Convert-ToBoolean -Value ([string]$xml.Mach1Settings.VerboseMode)
        ReleaseTag = [string]$xml.Mach1Settings.ReleaseTag
        PreparedUtc = [string]$xml.Mach1Settings.PreparedUtc
        HostProductName = [string]$xml.Mach1Settings.HostProductName
        HostBuild = [string]$xml.Mach1Settings.HostBuild
    }
}

function Write-BridgeResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$ReleaseTag,

        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($null -eq $script:Mach1Root) {
        return
    }

    try {
        $configDir = Join-Path -Path $script:Mach1Root -ChildPath 'Config'
        if (-not (Test-Path -LiteralPath $configDir)) {
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        }

        $resultPath = Join-Path -Path $configDir -ChildPath 'last-winre-result.json'
        $payload = [pscustomobject]@{
            sessionId = $SessionId
            releaseTag = $ReleaseTag
            success = $Success
            message = $Message
            completedUtc = [DateTime]::UtcNow.ToString('O')
        }

        $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $resultPath -Encoding UTF8
    }
    catch {
        Write-M1Log -Level 'WARN' -Always -Message "Could not write WinRE bridge result: $($_.Exception.Message)"
    }
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

    Write-M1Log -Level 'SUCCESS' -Message "$Path\\$Name = $Value"
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

    Write-M1Log -Level 'SUCCESS' -Message "$Path\\$Name = $Value"
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

function Resolve-ModulePlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OptimizationProfile,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$OfflineProfile,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Settings
    )

    $profile = if ([string]::IsNullOrWhiteSpace($OptimizationProfile)) { 'Recommended' } else { $OptimizationProfile }

    if ($profile -ieq 'Ultra') {
        return [pscustomobject]@{ Profile = 'Ultra'; Kernel = $true; Service = $true; Cs2 = $true }
    }

    if ($profile -ieq 'Light') {
        return [pscustomobject]@{ Profile = 'Light'; Kernel = $false; Service = $false; Cs2 = $true }
    }

    if ($OfflineProfile.IsWindows10Ltsc) {
        return [pscustomobject]@{ Profile = 'Recommended'; Kernel = $true; Service = $true; Cs2 = $true }
    }

    if ($OfflineProfile.IsWindows11) {
        return [pscustomobject]@{ Profile = 'Recommended'; Kernel = $true; Service = $false; Cs2 = $true }
    }

    return [pscustomobject]@{ Profile = 'Recommended'; Kernel = $true; Service = $true; Cs2 = $false }
}

function Invoke-KernelTimerModule {
    Write-M1Log -Level 'INFO' -Always -Message 'Applying Kernel/Timer module...'

    $cmdA = & bcdedit /set disabledynamictick yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "BCDEdit failed for disabledynamictick. Output: $($cmdA -join ' ')"
    }

    $cmdB = & bcdedit /set useplatformclock no 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "BCDEdit failed for useplatformclock. Output: $($cmdB -join ' ')"
    }

    $cmdC = & bcdedit /set tscsyncpolicy Enhanced 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "BCDEdit failed for tscsyncpolicy. Output: $($cmdC -join ' ')"
    }

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
    Write-M1Log -Level 'INFO' -Always -Message 'Applying Game Optimization module...'

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

    Invoke-RegSetDword -Path 'HKLM\OFFLINE_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions' -Name 'CpuPriorityClass' -Value '3'
    Invoke-RegSetDword -Path 'HKLM\OFFLINE_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions' -Name 'IoPriority' -Value '3'

    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'cs2.exe' -Value 'GpuPreference=2;'
    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Mouse' -Name 'MouseTrails' -Value '0'
    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0'
    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0'
    Invoke-RegSetString -Path 'HKU\OFFLINE_NTUSER\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0'
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
}

function Reboot-BackToWindows {
    Write-M1Log -Level 'INFO' -Always -Message 'Rebooting back to live Windows...'
    Close-RecoveryUi
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
    Close-RecoveryUi
    & wpeutil reboot
    exit 1
}

$settings = $null

try {
    $windowsDrive = Get-WindowsDrive
    $script:Mach1Root = Get-Mach1Root -WindowsDrive $windowsDrive
    $script:LogPath = Join-Path -Path $script:Mach1Root -ChildPath 'Logs\mach1-winre.log'

    $logoPath = Join-Path -Path $script:Mach1Root -ChildPath 'Config\mach1-logo.png'
    Try-InitializeRecoveryUi -LogoPath $logoPath

    Set-RecoveryUiProgress -TotalPercent 4 -CurrentPercent 10 -Status 'Initializing recovery session' -CurrentStep 'Locating pending trigger and settings'

    $pendingFile = Join-Path -Path $script:Mach1Root -ChildPath 'Config\patch.pending'
    if (-not (Test-Path -LiteralPath $pendingFile)) {
        Write-M1Log -Level 'WARN' -Always -Message 'No pending patch trigger found. Launching recovery menu.'
        Start-Process -FilePath 'X:\Windows\System32\RecEnv.exe' -ErrorAction SilentlyContinue
        exit 0
    }

    $settingsPath = Join-Path -Path $script:Mach1Root -ChildPath 'Config\settings.xml'
    $settings = Read-Mach1Settings -SettingsPath $settingsPath
    $script:VerboseMode = [bool]$settings.VerboseMode

    $pendingRaw = Get-Content -Path $pendingFile -Raw -ErrorAction SilentlyContinue
    $pendingParts = @($pendingRaw -split '\|')
    if ($pendingParts.Count -lt 5) {
        throw 'Invalid pending trigger format. Session handshake cannot be validated.'
    }

    $pendingRelease = [string]$pendingParts[2]
    $pendingSessionId = [string]$pendingParts[3]

    if ([string]::IsNullOrWhiteSpace([string]$settings.SessionId)) {
        throw 'SessionId was missing in settings.xml from Stage 1.'
    }

    if ($pendingSessionId -ne [string]$settings.SessionId) {
        throw "Session handshake mismatch. pending=$pendingSessionId settings=$($settings.SessionId)"
    }

    if ($pendingRelease -ne [string]$settings.ReleaseTag) {
        throw "Release handshake mismatch. pending=$pendingRelease settings=$($settings.ReleaseTag)"
    }

    Set-RecoveryUiProgress -TotalPercent 12 -CurrentPercent 35 -Status 'Handshake validated' -CurrentStep 'Loading offline hives'

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

    Mount-OfflineHive -Root 'HKLM' -Name 'OFFLINE_SYSTEM' -HiveFile $offlineSystem
    Mount-OfflineHive -Root 'HKLM' -Name 'OFFLINE_SOFTWARE' -HiveFile $offlineSoftware
    Mount-OfflineHive -Root 'HKU' -Name 'OFFLINE_NTUSER' -HiveFile $offlineNtUser[0]

    $osProfile = Get-OfflineOsProfile
    $modulePlan = Resolve-ModulePlan -OptimizationProfile ([string]$settings.OptimizationProfile) -OfflineProfile $osProfile -Settings $settings

    Set-RecoveryUiMeta -Host ("$($osProfile.ProductName) | Edition $($osProfile.Edition)") -Profile ([string]$modulePlan.Profile)
    Set-RecoveryUiProgress -TotalPercent 24 -CurrentPercent 100 -Status 'Offline system loaded' -CurrentStep 'Preparing module execution plan'

    $steps = New-Object System.Collections.ArrayList
    if ($modulePlan.Kernel) { [void]$steps.Add([pscustomobject]@{ Name = 'Kernel and timer tuning'; Action = { Invoke-KernelTimerModule } }) }
    if ($modulePlan.Service) { [void]$steps.Add([pscustomobject]@{ Name = 'Service hardening'; Action = { Invoke-ServiceHardeningModule } }) }
    if ($modulePlan.Cs2) { [void]$steps.Add([pscustomobject]@{ Name = 'Game optimization'; Action = { Invoke-GameOptimizationModule } }) }

    if ($steps.Count -eq 0) {
        Write-M1Log -Level 'SKIP' -Always -Message 'No modules selected by profile logic.'
    }

    $basePercent = 24
    $execSpan = 60
    $perStep = if ($steps.Count -gt 0) { [Math]::Floor($execSpan / $steps.Count) } else { $execSpan }

    for ($i = 0; $i -lt $steps.Count; $i++) {
        $step = $steps[$i]
        $startPercent = $basePercent + ($i * $perStep)
        $endPercent = if ($i -eq $steps.Count - 1) { $basePercent + $execSpan } else { $startPercent + $perStep }

        Set-RecoveryUiProgress -TotalPercent $startPercent -CurrentPercent 10 -Status "Running $($step.Name)" -CurrentStep $step.Name
        Write-M1Log -Level 'INFO' -Always -Message "Executing module: $($step.Name)"

        & $step.Action

        Set-RecoveryUiProgress -TotalPercent $endPercent -CurrentPercent 100 -Status "$($step.Name) complete" -CurrentStep $step.Name
    }

    Set-RecoveryUiProgress -TotalPercent 90 -CurrentPercent 30 -Status 'Finalizing changes' -CurrentStep 'Cleanup and trigger removal'
    Cleanup-Hives
    Clear-StartupTrigger

    Set-RecoveryUiProgress -TotalPercent 100 -CurrentPercent 100 -Status 'Completed' -CurrentStep 'Recovery execution complete'
    Write-M1Log -Level 'SUCCESS' -Always -Message 'All offline operations completed successfully.'
    Write-BridgeResult -SessionId ([string]$settings.SessionId) -ReleaseTag ([string]$settings.ReleaseTag) -Success $true -Message 'Offline patch execution completed successfully.'

    Start-Sleep -Seconds 2
    Reboot-BackToWindows
}
catch {
    if ($null -ne $settings -and $null -ne $settings.SessionId) {
        Write-BridgeResult -SessionId ([string]$settings.SessionId) -ReleaseTag ([string]$settings.ReleaseTag) -Success $false -Message ("Critical WinRE engine failure: $($_.Exception.Message)")
    }

    Abort-And-Reboot -Reason ("Critical WinRE engine failure: $($_.Exception.Message)")
}
