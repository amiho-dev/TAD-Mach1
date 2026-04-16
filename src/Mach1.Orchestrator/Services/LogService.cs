using System.IO;

namespace Mach1.Orchestrator.Services;

public sealed class LogService
{
    private static readonly object SyncRoot = new();

    public void Info(string message)
    {
        Write("INFO", message);
    }

    public void Warn(string message)
    {
        Write("WARN", message);
    }

    public void Error(string message)
    {
        Write("ERROR", message);
    }

    private static void Write(string level, string message)
    {
        Directory.CreateDirectory(Mach1Paths.LogDirectory);
        var stamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        var line = $"[{stamp}] [{Mach1Paths.Brand}] [{level}] {message}";

        lock (SyncRoot)
        {
            File.AppendAllText(Mach1Paths.OrchestratorLogPath, line + Environment.NewLine);
        }
    }
}
