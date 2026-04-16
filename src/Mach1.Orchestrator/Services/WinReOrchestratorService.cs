using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Mach1.Orchestrator.Models;

namespace Mach1.Orchestrator.Services;

public sealed class WinReOrchestratorService
{
    private readonly InstallerService _installerService;
    private readonly CommandRunner _commandRunner;
    private readonly LogService _logService;

    public WinReOrchestratorService(InstallerService installerService, CommandRunner commandRunner, LogService logService)
    {
        _installerService = installerService;
        _commandRunner = commandRunner;
        _logService = logService;
    }

    public async Task<PreparationResult> PreparePatchBootAsync(Mach1Settings settings, CancellationToken cancellationToken = default)
    {
        try
        {
            EnsureEngineScriptExists();

            if (File.Exists(Mach1Paths.LastWinReResultPath))
            {
                File.Delete(Mach1Paths.LastWinReResultPath);
            }

            _installerService.ArmPendingPatchTrigger(settings);

            await EnsureWinReEnabledAsync(cancellationToken).ConfigureAwait(false);

            var winReWimPath = await ResolveWinReWimPathAsync(cancellationToken).ConfigureAwait(false);
            await InjectWinReStartupAsync(winReWimPath, cancellationToken).ConfigureAwait(false);

            var boottore = await _commandRunner.RunAsync("reagentc.exe", "/boottore", cancellationToken).ConfigureAwait(false);
            if (!boottore.Success)
            {
                _logService.Error($"reagentc /boottore failed. stdout={boottore.StandardOutput} stderr={boottore.StandardError}");
                _installerService.ClearPendingPatchTrigger();
                return PreparationResult.Fail("Could not arm WinRE one-time boot.");
            }

            _logService.Info($"Patch flow armed for release {settings.ReleaseTag}.");
            return PreparationResult.Ok("WinRE patch flow armed. Reboot will enter recovery patch stage.");
        }
        catch (Exception ex)
        {
            _installerService.ClearPendingPatchTrigger();
            _logService.Error($"WinRE preparation failed: {ex.Message}");
            return PreparationResult.Fail(ex.Message);
        }
    }

    public async Task<PreparationResult> RebootNowAsync(CancellationToken cancellationToken = default)
    {
        var rebootResult = await _commandRunner.RunAsync("shutdown.exe", "/r /t 0", cancellationToken).ConfigureAwait(false);

        if (!rebootResult.Success)
        {
            _logService.Error($"shutdown failed. stdout={rebootResult.StandardOutput} stderr={rebootResult.StandardError}");
            return PreparationResult.Fail("Windows reboot command failed.");
        }

        return PreparationResult.Ok("Reboot command submitted.");
    }

    private async Task<string> ResolveWinReWimPathAsync(CancellationToken cancellationToken)
    {
        var defaultPath = @"C:\Windows\System32\Recovery\Winre.wim";
        if (File.Exists(defaultPath))
        {
            return defaultPath;
        }

        var info = await _commandRunner.RunAsync("reagentc.exe", "/info", cancellationToken).ConfigureAwait(false);
        var text = string.Join(Environment.NewLine, info.StandardOutput, info.StandardError);

        var match = Regex.Match(text, @"Windows RE location\s*:\s*(?<loc>.+)", RegexOptions.IgnoreCase);
        if (match.Success)
        {
            var location = match.Groups["loc"].Value.Trim();
            if (!string.IsNullOrWhiteSpace(location))
            {
                var candidate = location.EndsWith("winre.wim", StringComparison.OrdinalIgnoreCase)
                    ? location
                    : Path.Combine(location, "Winre.wim");

                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
        }

        throw new InvalidOperationException("WinRE image (Winre.wim) could not be resolved.");
    }

    private async Task InjectWinReStartupAsync(string wimPath, CancellationToken cancellationToken)
    {
        var mountDir = Mach1Paths.WinReMountDirectory;
        Directory.CreateDirectory(mountDir);

        await TryDiscardPreviousMountAsync(mountDir, cancellationToken).ConfigureAwait(false);

        var mounted = false;
        try
        {
            var mount = await _commandRunner.RunAsync(
                "dism.exe",
                $"/Mount-Image /ImageFile:\"{wimPath}\" /Index:1 /MountDir:\"{mountDir}\"",
                cancellationToken).ConfigureAwait(false);

            if (!mount.Success)
            {
                throw new InvalidOperationException($"DISM mount failed: {mount.StandardOutput} {mount.StandardError}");
            }

            mounted = true;

            var targetEngineDirectory = Path.Combine(mountDir, "Windows", "System32", "Mach1");
            Directory.CreateDirectory(targetEngineDirectory);
            var targetEnginePath = Path.Combine(targetEngineDirectory, "WinReEngine.ps1");
            File.Copy(Mach1Paths.InstalledEngineScriptPath, targetEnginePath, overwrite: true);

            var winpeshlPath = Path.Combine(mountDir, "Windows", "System32", "winpeshl.ini");
            File.WriteAllText(winpeshlPath, BuildWinPeshlIni(), Encoding.ASCII);

            var unmountCommit = await _commandRunner.RunAsync(
                "dism.exe",
                $"/Unmount-Image /MountDir:\"{mountDir}\" /Commit",
                cancellationToken).ConfigureAwait(false);

            if (!unmountCommit.Success)
            {
                throw new InvalidOperationException($"DISM unmount commit failed: {unmountCommit.StandardOutput} {unmountCommit.StandardError}");
            }

            mounted = false;
            _logService.Info("WinRE startup script injection completed using winpeshl.ini.");
        }
        catch
        {
            if (mounted)
            {
                await _commandRunner.RunAsync("dism.exe", $"/Unmount-Image /MountDir:\"{mountDir}\" /Discard", cancellationToken).ConfigureAwait(false);
            }

            throw;
        }
    }

    private async Task TryDiscardPreviousMountAsync(string mountDir, CancellationToken cancellationToken)
    {
        if (!Directory.Exists(mountDir))
        {
            Directory.CreateDirectory(mountDir);
            return;
        }

        await _commandRunner.RunAsync("dism.exe", $"/Unmount-Image /MountDir:\"{mountDir}\" /Discard", cancellationToken).ConfigureAwait(false);
    }

    private static string BuildWinPeshlIni()
    {
        return string.Join(Environment.NewLine,
            "[LaunchApps]",
            "X:\\Windows\\System32\\wpeinit.exe",
            "X:\\Windows\\System32\\cmd.exe,/c X:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File X:\\Windows\\System32\\Mach1\\WinReEngine.ps1");
    }

    private async Task EnsureWinReEnabledAsync(CancellationToken cancellationToken)
    {
        var info = await _commandRunner.RunAsync("reagentc.exe", "/info", cancellationToken).ConfigureAwait(false);
        var text = string.Join(Environment.NewLine, info.StandardOutput, info.StandardError);
        if (!text.Contains("Windows RE status", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (!text.Contains("Enabled", StringComparison.OrdinalIgnoreCase))
        {
            var enable = await _commandRunner.RunAsync("reagentc.exe", "/enable", cancellationToken).ConfigureAwait(false);
            if (!enable.Success)
            {
                throw new InvalidOperationException($"reagentc /enable failed: {enable.StandardOutput} {enable.StandardError}");
            }
        }
    }

    private static void EnsureEngineScriptExists()
    {
        if (!File.Exists(Mach1Paths.InstalledEngineScriptPath))
        {
            throw new FileNotFoundException($"WinRE engine script missing at {Mach1Paths.InstalledEngineScriptPath}");
        }
    }
}

public sealed record PreparationResult(bool Success, string Message)
{
    public static PreparationResult Ok(string message) => new(true, message);

    public static PreparationResult Fail(string message) => new(false, message);
}
