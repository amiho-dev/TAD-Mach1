using System.Windows;
using System.Windows.Input;
using Microsoft.Win32;
using Mach1.Orchestrator.Models;
using Mach1.Orchestrator.Services;

namespace Mach1.Orchestrator;

public partial class MainWindow : Window
{
    private readonly LogService _logService;
    private readonly CommandRunner _commandRunner;
    private readonly InstallerService _installerService;
    private readonly SettingsService _settingsService;
    private readonly BackupService _backupService;
    private readonly WinReOrchestratorService _winReOrchestratorService;
    private readonly UpdaterService _updaterService;
    private readonly BridgeService _bridgeService;

    private bool _backupCompleted;
    private bool _isUpdating;
    private string _hostProductName = "Windows";
    private int _hostBuild;
    private bool _isWindows11Like;
    private bool _isWindows10Ltsc;

    public MainWindow()
    {
        InitializeComponent();

        _logService = new LogService();
        _commandRunner = new CommandRunner();
        _installerService = new InstallerService(_logService);
        _settingsService = new SettingsService(_logService);
        _backupService = new BackupService(_commandRunner, _logService);
        _winReOrchestratorService = new WinReOrchestratorService(_installerService, _commandRunner, _logService);
        _updaterService = new UpdaterService(_logService);
        _bridgeService = new BridgeService(_logService);
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            _installerService.EnsureInstalled();
            TxtVersion.Text = $"Release: {Mach1Paths.CurrentRelease}";

            DetectHost();
            TxtOsInfo.Text = BuildHostSummary();

            var loaded = _settingsService.LoadOrDefault();
            ApplySettingsToUi(loaded);

            var bridgeResult = _bridgeService.ReadLastResult();
            if (bridgeResult is not null)
            {
                var bridgeState = bridgeResult.Success ? "SUCCESS" : "FAILED";
                SetStatus($"Last recovery session {bridgeState}: {bridgeResult.Message} ({bridgeResult.CompletedUtc})");
            }
            else
            {
                SetStatus("Ready. Select profile, configure safety checks, then start recovery execution.");
            }

            await CheckForUpdatesAsync(autoMode: true);
        }
        catch (Exception ex)
        {
            SetStatus($"Initialization failed: {ex.Message}");
            _logService.Error($"Window init error: {ex}");
        }
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
            return;
        }

        DragMove();
    }

    private void BtnMinimizeWindow_Click(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState.Minimized;
    }

    private void BtnCloseWindow_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private async void BtnCreateBackup_Click(object sender, RoutedEventArgs e)
    {
        SetBusy(true);
        SetStatus("Creating System Restore Point...");

        try
        {
            var ok = await _backupService.CreateSystemRestorePointAsync();
            _backupCompleted = ok;
            SetStatus(ok
                ? "Backup completed. Recovery execution can proceed."
                : "Backup failed. Use backup bypass only if you accept full risk.");
        }
        catch (Exception ex)
        {
            _backupCompleted = false;
            SetStatus($"Backup exception: {ex.Message}");
            _logService.Error($"Backup exception: {ex}");
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void BtnSaveConfig_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var settings = BuildSettingsFromUi();
            _settingsService.Save(settings);
            SetStatus($"Configuration saved with {settings.OptimizationProfile} profile.");
        }
        catch (Exception ex)
        {
            SetStatus($"Saving config failed: {ex.Message}");
            _logService.Error($"Save config failed: {ex}");
        }
    }

    private async void BtnPatch_Click(object sender, RoutedEventArgs e)
    {
        if (!ValidatePatchReadiness(out var reason))
        {
            SetStatus(reason);
            return;
        }

        SetBusy(true);
        SetStatus("Preparing recovery environment startup and offline execution plan...");

        try
        {
            var settings = BuildSettingsFromUi();
            _settingsService.Save(settings);

            var prep = await _winReOrchestratorService.PreparePatchBootAsync(settings);
            if (!prep.Success)
            {
                SetStatus($"Recovery preparation failed: {prep.Message}");
                return;
            }

            var answer = MessageBox.Show(
                "Configuration is complete. Windows will reboot into Recovery Environment and execute the selected profile. Reboot now?",
                "Mach1 Recovery Execution",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);

            if (answer != MessageBoxResult.Yes)
            {
                SetStatus("Recovery run is prepared and will execute on next reboot.");
                return;
            }

            var reboot = await _winReOrchestratorService.RebootNowAsync();
            if (!reboot.Success)
            {
                SetStatus($"Reboot command failed: {reboot.Message}");
                return;
            }

            SetStatus("Reboot command submitted. Recovery execution will start shortly.");
        }
        catch (Exception ex)
        {
            SetStatus($"Unexpected failure: {ex.Message}");
            _logService.Error($"Recovery flow failed: {ex}");
        }
        finally
        {
            SetBusy(false);
        }
    }

    private Mach1Settings BuildSettingsFromUi()
    {
        var profile = GetSelectedProfile();
        var modules = ResolveModules(profile, _isWindows11Like, _isWindows10Ltsc);

        return new Mach1Settings
        {
            SessionId = Guid.NewGuid().ToString("N"),
            OptimizationProfile = profile,
            KernelTimerTweaks = modules.Kernel,
            ServiceHardening = modules.Service,
            Cs2PerformancePack = modules.Cs2,
            VerboseMode = ChkVerbose.IsChecked == true,
            BackupToggleConfirmed = ChkBackupToggle.IsChecked == true,
            BackupBypassConfirmed = ChkBackupBypass.IsChecked == true,
            BackupCompleted = _backupCompleted,
            HostProductName = _hostProductName,
            HostBuild = _hostBuild,
            ReleaseTag = Mach1Paths.CurrentRelease,
            PreparedUtc = DateTime.UtcNow.ToString("O")
        };
    }

    private void ApplySettingsToUi(Mach1Settings settings)
    {
        var profile = string.IsNullOrWhiteSpace(settings.OptimizationProfile)
            ? "Recommended"
            : settings.OptimizationProfile;

        RdoRecommended.IsChecked = profile.Equals("Recommended", StringComparison.OrdinalIgnoreCase);
        RdoUltra.IsChecked = profile.Equals("Ultra", StringComparison.OrdinalIgnoreCase);
        RdoLight.IsChecked = profile.Equals("Light", StringComparison.OrdinalIgnoreCase);

        if (RdoRecommended.IsChecked != true && RdoUltra.IsChecked != true && RdoLight.IsChecked != true)
        {
            RdoRecommended.IsChecked = true;
        }

        ChkVerbose.IsChecked = settings.VerboseMode;
        ChkBackupToggle.IsChecked = settings.BackupToggleConfirmed;
        ChkBackupBypass.IsChecked = settings.BackupBypassConfirmed;
        _backupCompleted = settings.BackupCompleted;
    }

    private bool ValidatePatchReadiness(out string reason)
    {
        if (ChkBackupToggle.IsChecked != true)
        {
            reason = "Confirm the recovery-execution acknowledgment before continuing.";
            return false;
        }

        if (!_backupCompleted && ChkBackupBypass.IsChecked != true)
        {
            reason = "Create Backup must complete, or explicitly enable backup bypass.";
            return false;
        }

        reason = string.Empty;
        return true;
    }

    private string GetSelectedProfile()
    {
        if (RdoUltra.IsChecked == true)
        {
            return "Ultra";
        }

        if (RdoLight.IsChecked == true)
        {
            return "Light";
        }

        return "Recommended";
    }

    private static (bool Kernel, bool Service, bool Cs2) ResolveModules(string profile, bool isWindows11Like, bool isWindows10Ltsc)
    {
        if (profile.Equals("Ultra", StringComparison.OrdinalIgnoreCase))
        {
            return (true, true, true);
        }

        if (profile.Equals("Light", StringComparison.OrdinalIgnoreCase))
        {
            return (false, false, true);
        }

        if (isWindows10Ltsc)
        {
            return (true, true, true);
        }

        if (isWindows11Like)
        {
            return (true, false, true);
        }

        return (true, true, false);
    }

    private void SetBusy(bool busy)
    {
        BtnCreateBackup.IsEnabled = !busy;
        BtnSaveConfig.IsEnabled = !busy;
        BtnPatch.IsEnabled = !busy;
        BtnCheckUpdates.IsEnabled = !busy && !_isUpdating;
    }

    private void SetStatus(string status)
    {
        TxtStatus.Text = status;
        _logService.Info(status);
    }

    private async void BtnCheckUpdates_Click(object sender, RoutedEventArgs e)
    {
        await CheckForUpdatesAsync(autoMode: false);
    }

    private async Task CheckForUpdatesAsync(bool autoMode)
    {
        if (_isUpdating)
        {
            return;
        }

        _isUpdating = true;
        BtnCheckUpdates.IsEnabled = false;

        try
        {
            TxtUpdateStatus.Text = autoMode
                ? "Checking GitHub for updates in the background..."
                : "Checking GitHub for updates...";

            var check = await _updaterService.CheckForUpdatesAsync();
            if (!check.Success)
            {
                TxtUpdateStatus.Text = check.Message;
                return;
            }

            if (!check.IsUpdateAvailable || check.Package is null)
            {
                TxtUpdateStatus.Text = check.Message;
                return;
            }

            TxtUpdateStatus.Text = $"{check.Message}. Downloading package...";
            var download = await _updaterService.DownloadAndStageAsync(check.Package);

            if (!download.Success)
            {
                TxtUpdateStatus.Text = download.Message;
                return;
            }

            if (download.InstallerLaunched)
            {
                TxtUpdateStatus.Text = $"{download.Message} Complete installer prompts to finish update.";
                SetStatus($"Update ready: {check.Package.Tag}");
                return;
            }

            var releaseText = string.IsNullOrWhiteSpace(check.Package.ReleaseUrl)
                ? string.Empty
                : $" | Release notes: {check.Package.ReleaseUrl}";
            TxtUpdateStatus.Text = $"{download.Message}{releaseText}";
            SetStatus($"Update downloaded for {check.Package.Tag}.");
        }
        finally
        {
            _isUpdating = false;
            BtnCheckUpdates.IsEnabled = true;
        }
    }

    private void DetectHost()
    {
        const string keyPath = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion";
        using var key = Registry.LocalMachine.OpenSubKey(keyPath);
        var productName = key?.GetValue("ProductName") as string;
        var buildText = (key?.GetValue("CurrentBuild") as string)
            ?? (key?.GetValue("CurrentBuildNumber") as string)
            ?? "0";

        _hostProductName = string.IsNullOrWhiteSpace(productName) ? "Windows" : productName;
        _hostBuild = int.TryParse(buildText, out var parsedBuild) ? parsedBuild : Environment.OSVersion.Version.Build;
        _isWindows11Like = _hostProductName.Contains("Windows 11", StringComparison.OrdinalIgnoreCase)
            || (_hostProductName.Contains("Windows 10", StringComparison.OrdinalIgnoreCase) && _hostBuild >= 22000);
        _isWindows10Ltsc = _hostProductName.Contains("Windows 10", StringComparison.OrdinalIgnoreCase)
            && (_hostProductName.Contains("LTSC", StringComparison.OrdinalIgnoreCase)
                || _hostProductName.Contains("EnterpriseS", StringComparison.OrdinalIgnoreCase)
                || _hostProductName.Contains("IoTEnterpriseS", StringComparison.OrdinalIgnoreCase));
    }

    private string BuildHostSummary()
    {
        var normalized = _hostProductName;
        if (!_hostProductName.Contains("Windows 11", StringComparison.OrdinalIgnoreCase)
            && _hostProductName.Contains("Windows 10", StringComparison.OrdinalIgnoreCase)
            && _hostBuild >= 22000)
        {
            normalized = _hostProductName.Replace("Windows 10", "Windows 11", StringComparison.OrdinalIgnoreCase);
        }

        var profileHint = _isWindows10Ltsc
            ? "LTSC policy set active"
            : _isWindows11Like ? "Windows 11 policy set active" : "Windows 10 policy set active";

        return $"Detected host: {normalized} (build {_hostBuild}). {profileHint}.";
    }
}
