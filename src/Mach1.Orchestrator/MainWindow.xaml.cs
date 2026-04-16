using System.Windows;
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

    private bool _backupCompleted;
    private bool _isUpdating;

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
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            _installerService.EnsureInstalled();
            TxtVersion.Text = $"Release: {Mach1Paths.CurrentRelease}";

            var loaded = _settingsService.LoadOrDefault();
            ApplySettingsToUi(loaded);

            TxtOsInfo.Text = BuildFriendlyOsLabel();
            SetStatus("Ready. Configure packs and run Create Backup before reboot-to-patch.");
            await CheckForUpdatesAsync(autoMode: true);
        }
        catch (Exception ex)
        {
            SetStatus($"Initialization failed: {ex.Message}");
            _logService.Error($"Window init error: {ex}");
        }
    }

    private async void BtnCreateBackup_Click(object sender, RoutedEventArgs e)
    {
        SetBusy(true);
        SetStatus("Creating System Restore Point...");

        try
        {
            var ok = await _backupService.CreateSystemRestorePointAsync();
            _backupCompleted = ok;

            if (ok)
            {
                SetStatus("Backup completed. You can now arm reboot-to-patch.");
            }
            else
            {
                SetStatus("Backup failed. Patch mode stays blocked.");
            }
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
            SetStatus("Selection saved to settings.xml.");
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
        SetStatus("Saving configuration and preparing WinRE image...");

        try
        {
            var settings = BuildSettingsFromUi();
            _settingsService.Save(settings);

            var prep = await _winReOrchestratorService.PreparePatchBootAsync(settings);
            if (!prep.Success)
            {
                SetStatus($"Patch preparation failed: {prep.Message}");
                return;
            }

            SetStatus("WinRE patch flow armed. Awaiting reboot confirmation.");

            var answer = MessageBox.Show(
                "Mach1 (by TAD) is armed for Recovery patching. Reboot immediately now?",
                "Mach1 (by TAD)",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);

            if (answer != MessageBoxResult.Yes)
            {
                SetStatus("Reboot deferred by user. Trigger remains armed for next reboot.");
                return;
            }

            var reboot = await _winReOrchestratorService.RebootNowAsync();
            if (!reboot.Success)
            {
                SetStatus($"Reboot command failed: {reboot.Message}");
            }
        }
        catch (Exception ex)
        {
            SetStatus($"Unexpected failure: {ex.Message}");
            _logService.Error($"Patch flow failed: {ex}");
        }
        finally
        {
            SetBusy(false);
        }
    }

    private Mach1Settings BuildSettingsFromUi()
    {
        return new Mach1Settings
        {
            KernelTimerTweaks = ChkKernelTimer.IsChecked == true,
            ServiceHardening = ChkServiceHardening.IsChecked == true,
            Cs2PerformancePack = ChkCs2Pack.IsChecked == true,
            VerboseMode = ChkVerbose.IsChecked == true,
            BackupToggleConfirmed = ChkBackupToggle.IsChecked == true,
            BackupCompleted = _backupCompleted,
            ReleaseTag = Mach1Paths.CurrentRelease
        };
    }

    private void ApplySettingsToUi(Mach1Settings settings)
    {
        ChkKernelTimer.IsChecked = settings.KernelTimerTweaks;
        ChkServiceHardening.IsChecked = settings.ServiceHardening;
        ChkCs2Pack.IsChecked = settings.Cs2PerformancePack;
        ChkVerbose.IsChecked = settings.VerboseMode;
        ChkBackupToggle.IsChecked = settings.BackupToggleConfirmed;
        _backupCompleted = settings.BackupCompleted;
    }

    private bool ValidatePatchReadiness(out string reason)
    {
        if (!IsAnyPackSelected())
        {
            reason = "Select at least one optimization pack.";
            return false;
        }

        if (ChkBackupToggle.IsChecked != true)
        {
            reason = "Mandatory BETA backup toggle is not confirmed.";
            return false;
        }

        if (!_backupCompleted)
        {
            reason = "Create Backup must complete successfully before patching.";
            return false;
        }

        reason = string.Empty;
        return true;
    }

    private bool IsAnyPackSelected()
    {
        return ChkKernelTimer.IsChecked == true
            || ChkServiceHardening.IsChecked == true
            || ChkCs2Pack.IsChecked == true;
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

    private static string BuildFriendlyOsLabel()
    {
        var version = Environment.OSVersion.Version;
        var productName = ReadWindowsProductName();
        var adjustedName = productName;

        if (productName.Contains("Windows 10", StringComparison.OrdinalIgnoreCase) && version.Build >= 22000)
        {
            adjustedName = productName.Replace("Windows 10", "Windows 11", StringComparison.OrdinalIgnoreCase);
        }

        return $"Detected host: {adjustedName} (build {version.Build}, kernel {version.Major}.{version.Minor}.{version.Build}). Win11-only removals remain skipped on Windows 10 LTSC.";
    }

    private static string ReadWindowsProductName()
    {
        const string keyPath = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion";
        using var key = Registry.LocalMachine.OpenSubKey(keyPath);
        var productName = key?.GetValue("ProductName") as string;
        return string.IsNullOrWhiteSpace(productName) ? "Windows" : productName;
    }
}
