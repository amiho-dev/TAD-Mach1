using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;

namespace Mach1.Setup;

public partial class MainWindow : Window
{
    private const string ReleaseTag = "Mach1.04166.501.CU";
    private const string ProgramFilesMainPath = @"C:\Program Files\Mach1\Orchestrator";
    private const string Mach1Root = @"C:\Mach1";
    private const string ConfigDirectory = @"C:\Mach1\Config";
    private const string RecoveryDirectory = @"C:\Mach1\WinRE";

    public MainWindow()
    {
        InitializeComponent();
    }

    private async void BtnInstall_Click(object sender, RoutedEventArgs e)
    {
        BtnInstall.IsEnabled = false;
        BtnLaunch.IsEnabled = false;

        try
        {
            var includeMain = ChkInstallMain.IsChecked == true;
            var includeRecovery = ChkInstallRecovery.IsChecked == true;
            if (!includeMain && !includeRecovery)
            {
                TxtLog.Text = "Select at least one component to install.";
                return;
            }

            await Task.Run(() => Install(includeMain, includeRecovery));
            InstallProgress.Value = 100;
            TxtLog.Text = "Installation completed successfully.";
            BtnLaunch.IsEnabled = includeMain;
        }
        catch (Exception ex)
        {
            TxtLog.Text = $"Installation failed: {ex.Message}";
        }
        finally
        {
            BtnInstall.IsEnabled = true;
        }
    }

    private void Install(bool includeMain, bool includeRecovery)
    {
        Directory.CreateDirectory(Mach1Root);
        Directory.CreateDirectory(ConfigDirectory);
        Directory.CreateDirectory(RecoveryDirectory);

        var baseDirectory = AppContext.BaseDirectory;
        var payloadRoot = Path.Combine(baseDirectory, "Payload");

        if (includeMain)
        {
            var sourceMain = Path.Combine(payloadRoot, "Mach1.Orchestrator");
            if (!Directory.Exists(sourceMain))
            {
                throw new InvalidOperationException("Missing main payload folder: Payload\\Mach1.Orchestrator");
            }

            CopyDirectory(sourceMain, ProgramFilesMainPath);
            SetProgress(55, "Main system binaries installed.");
        }

        if (includeRecovery)
        {
            var sourceEngine = Path.Combine(payloadRoot, "WinReEngine.ps1");
            if (!File.Exists(sourceEngine))
            {
                throw new InvalidOperationException("Missing WinRE payload file: Payload\\WinReEngine.ps1");
            }

            File.Copy(sourceEngine, Path.Combine(RecoveryDirectory, "WinReEngine.ps1"), overwrite: true);
            SetProgress(85, "Recovery engine installed.");
        }

        var manifest = new
        {
            releaseTag = ReleaseTag,
            installedUtc = DateTime.UtcNow.ToString("O"),
            includeMain,
            includeRecovery,
            installerVersion = ReleaseTag,
            mainInstallPath = ProgramFilesMainPath,
            recoveryInstallPath = Path.Combine(RecoveryDirectory, "WinReEngine.ps1")
        };

        var manifestPath = Path.Combine(ConfigDirectory, "install-manifest.json");
        File.WriteAllText(manifestPath, JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }));
        SetProgress(95, "Install manifest written.");
    }

    private void SetProgress(double value, string message)
    {
        Dispatcher.Invoke(() =>
        {
            InstallProgress.Value = value;
            TxtLog.Text = message;
        });
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);

        foreach (var directory in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(source, directory);
            Directory.CreateDirectory(Path.Combine(destination, relative));
        }

        foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(source, file);
            var target = Path.Combine(destination, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite: true);
        }
    }

    private void BtnLaunch_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var exePath = Path.Combine(ProgramFilesMainPath, "Mach1.Orchestrator.exe");
            if (!File.Exists(exePath))
            {
                TxtLog.Text = "Launch failed: Mach1.Orchestrator.exe is missing in Program Files.";
                return;
            }

            Process.Start(new ProcessStartInfo(exePath)
            {
                UseShellExecute = true,
                Verb = "runas"
            });
        }
        catch (Exception ex)
        {
            TxtLog.Text = $"Launch failed: {ex.Message}";
        }
    }
}
