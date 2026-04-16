using System.IO;

namespace Mach1.Orchestrator.Services;

public sealed class InstallerService
{
    private readonly LogService _logService;

    public InstallerService(LogService logService)
    {
        _logService = logService;
    }

    public void EnsureInstalled()
    {
        Directory.CreateDirectory(Mach1Paths.Root);
        Directory.CreateDirectory(Mach1Paths.ConfigDirectory);
        Directory.CreateDirectory(Mach1Paths.LogDirectory);
        Directory.CreateDirectory(Mach1Paths.WinReDirectory);
        Directory.CreateDirectory(Mach1Paths.WinReMountDirectory);
        Directory.CreateDirectory(Mach1Paths.WinReWorkDirectory);
        Directory.CreateDirectory(Mach1Paths.UpdatesDirectory);

        EnsureBundledEngineScriptInstalled();
        WriteBetaNotice();

        _logService.Info("Installer logic completed. Directory root is C:\\Mach1.");
    }

    public void ArmPendingPatchTrigger()
    {
        var triggerContent = $"{Mach1Paths.Brand}|{DateTime.UtcNow:O}|{Mach1Paths.CurrentRelease}";
        File.WriteAllText(Mach1Paths.PendingFlagPath, triggerContent);
        _logService.Info("Pending patch trigger created.");
    }

    public void ClearPendingPatchTrigger()
    {
        if (File.Exists(Mach1Paths.PendingFlagPath))
        {
            File.Delete(Mach1Paths.PendingFlagPath);
            _logService.Info("Pending patch trigger cleared.");
        }
    }

    private void EnsureBundledEngineScriptInstalled()
    {
        var sourceScript = Path.Combine(AppContext.BaseDirectory, "Assets", "WinReEngine.ps1");
        if (!File.Exists(sourceScript))
        {
            _logService.Warn($"Bundled WinRE script not found at {sourceScript}.");
            return;
        }

        File.Copy(sourceScript, Mach1Paths.InstalledEngineScriptPath, overwrite: true);
        _logService.Info("WinRE engine script copied to C:\\Mach1\\WinRE.");
    }

    private void WriteBetaNotice()
    {
        var betaInfoPath = Path.Combine(Mach1Paths.ConfigDirectory, "beta-info.txt");
        var text = string.Join(Environment.NewLine,
            "Mach1 (by TAD)",
            "BETA - Use at your own risk.",
            "This build prepares a reboot-to-WinRE patching flow.",
            "Mandatory backup is required before enabling patch mode.",
            $"Release: {Mach1Paths.CurrentRelease}");

        File.WriteAllText(betaInfoPath, text);
    }
}
