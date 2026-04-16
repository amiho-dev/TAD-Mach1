using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Windows;

namespace Mach1.Setup;

public partial class MainWindow : Window
{
    private const string ReleaseTag = "Mach1.04166.503.BF";
    private const string ProgramFilesMainPath = @"C:\Program Files\Mach1\Orchestrator";
    private const string Mach1Root = @"C:\Mach1";
    private const string ConfigDirectory = @"C:\Mach1\Config";
    private const string RecoveryDirectory = @"C:\Mach1\WinRE";
    private readonly bool _updateMode;

    public MainWindow()
    {
        InitializeComponent();

        _updateMode = Environment.GetCommandLineArgs()
            .Any(a => string.Equals(a, "-update", StringComparison.OrdinalIgnoreCase));

        if (_updateMode)
        {
            TxtInstallerTitle.Text = "Mach1 Installer (Update Mode)";
            TxtMode.Text = "Mode: In-place update";
            BtnInstall.Content = "Update";
            ChkInstallMain.IsChecked = true;
            ChkInstallRecovery.IsChecked = true;
            ChkInstallMain.IsEnabled = false;
            ChkInstallRecovery.IsEnabled = false;
            TxtLog.Text = "Ready to apply in-place update from bundled payload.";
        }
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

            await Task.Run(() => Install(includeMain, includeRecovery, _updateMode));
            InstallProgress.Value = 100;
            TxtLog.Text = _updateMode
                ? "Update completed successfully."
                : "Installation completed successfully.";
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

    private void Install(bool includeMain, bool includeRecovery, bool updateMode)
    {
        Directory.CreateDirectory(Mach1Root);
        Directory.CreateDirectory(ConfigDirectory);
        Directory.CreateDirectory(RecoveryDirectory);

        var payloadRoot = ResolvePayloadRoot();

        SetProgress(15, updateMode
            ? "Update mode started. Validating payload..."
            : "Install mode started. Validating payload...");

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
            updateMode,
            installerVersion = ReleaseTag,
            mainInstallPath = ProgramFilesMainPath,
            recoveryInstallPath = Path.Combine(RecoveryDirectory, "WinReEngine.ps1")
        };

        var manifestPath = Path.Combine(ConfigDirectory, "install-manifest.json");
        File.WriteAllText(manifestPath, JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }));
        SetProgress(95, "Install manifest written.");
    }

    private static string ResolvePayloadRoot()
    {
        var embeddedPayload = TryExtractEmbeddedPayload();
        if (!string.IsNullOrWhiteSpace(embeddedPayload))
        {
            return embeddedPayload;
        }

        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "Payload"),
            Path.Combine(Path.GetDirectoryName(Environment.ProcessPath ?? string.Empty) ?? string.Empty, "Payload"),
            Path.Combine(Environment.CurrentDirectory, "Payload")
        }
        .Where(p => !string.IsNullOrWhiteSpace(p))
        .Distinct(StringComparer.OrdinalIgnoreCase);

        foreach (var candidate in candidates)
        {
            if (!Directory.Exists(candidate))
            {
                continue;
            }

            var mainPath = Path.Combine(candidate, "Mach1.Orchestrator");
            var rePath = Path.Combine(candidate, "WinReEngine.ps1");
            if (Directory.Exists(mainPath) && File.Exists(rePath))
            {
                return candidate;
            }
        }

        var zipCandidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "Payload", "payload.zip"),
            Path.Combine(Path.GetDirectoryName(Environment.ProcessPath ?? string.Empty) ?? string.Empty, "Payload", "payload.zip"),
            Path.Combine(Environment.CurrentDirectory, "Payload", "payload.zip")
        }
        .Distinct(StringComparer.OrdinalIgnoreCase);

        foreach (var zipPath in zipCandidates)
        {
            if (!File.Exists(zipPath))
            {
                continue;
            }

            var extractRoot = Path.Combine(Path.GetTempPath(), "Mach1SetupPayload", ReleaseTag);
            if (Directory.Exists(extractRoot))
            {
                Directory.Delete(extractRoot, recursive: true);
            }

            Directory.CreateDirectory(extractRoot);
            ZipFile.ExtractToDirectory(zipPath, extractRoot);

            var extractedPayload = Path.Combine(extractRoot, "Payload");
            var mainPath = Path.Combine(extractedPayload, "Mach1.Orchestrator");
            var rePath = Path.Combine(extractedPayload, "WinReEngine.ps1");
            if (Directory.Exists(mainPath) && File.Exists(rePath))
            {
                return extractedPayload;
            }
        }

        throw new InvalidOperationException("Missing bundled payload. Expected Payload/Mach1.Orchestrator and Payload/WinReEngine.ps1.");
    }

    private static string? TryExtractEmbeddedPayload()
    {
        var assembly = Assembly.GetExecutingAssembly();
        const string resourceName = "Mach1.Setup.Payload.payload.zip";

        using var stream = assembly.GetManifestResourceStream(resourceName);
        if (stream is null)
        {
            return null;
        }

        var extractRoot = Path.Combine(Path.GetTempPath(), "Mach1SetupPayload", ReleaseTag);
        var payloadRoot = Path.Combine(extractRoot, "Payload");

        if (Directory.Exists(payloadRoot))
        {
            return payloadRoot;
        }

        if (Directory.Exists(extractRoot))
        {
            Directory.Delete(extractRoot, recursive: true);
        }

        Directory.CreateDirectory(extractRoot);
        var zipPath = Path.Combine(extractRoot, "payload.zip");

        using (var outFile = File.Create(zipPath))
        {
            stream.CopyTo(outFile);
        }

        ZipFile.ExtractToDirectory(zipPath, extractRoot);
        File.Delete(zipPath);

        return Directory.Exists(payloadRoot) ? payloadRoot : null;
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
