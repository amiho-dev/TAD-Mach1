using System.IO;

namespace Mach1.Orchestrator.Services;

public sealed class BackupService
{
    private readonly CommandRunner _commandRunner;
    private readonly LogService _logService;

    public BackupService(CommandRunner commandRunner, LogService logService)
    {
        _commandRunner = commandRunner;
        _logService = logService;
    }

    public async Task<bool> CreateSystemRestorePointAsync(CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(Mach1Paths.WinReWorkDirectory);
        var scriptPath = Path.Combine(Mach1Paths.WinReWorkDirectory, "CreateBackup.ps1");

        var scriptContent = string.Join(Environment.NewLine,
            "$ErrorActionPreference = 'Stop'",
            "Enable-ComputerRestore -Drive ($env:SystemDrive + '\\') -ErrorAction SilentlyContinue | Out-Null",
            "Checkpoint-Computer -Description 'Mach1 (by TAD) BETA Backup' -RestorePointType 'MODIFY_SETTINGS' | Out-Null");

        File.WriteAllText(scriptPath, scriptContent);

        var result = await _commandRunner.RunAsync(
            "powershell.exe",
            $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
            cancellationToken).ConfigureAwait(false);

        if (result.Success)
        {
            _logService.Info("System Restore Point creation completed.");
            return true;
        }

        _logService.Error($"System Restore Point failed. stdout={result.StandardOutput} stderr={result.StandardError}");
        return false;
    }
}
