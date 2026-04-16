namespace Mach1.Orchestrator.Models;

public sealed class Mach1Settings
{
    public string SessionId { get; set; } = Guid.NewGuid().ToString("N");

    public bool KernelTimerTweaks { get; set; }

    public bool ServiceHardening { get; set; }

    public bool Cs2PerformancePack { get; set; }

    public bool VerboseMode { get; set; }

    public bool BackupToggleConfirmed { get; set; }

    public bool BackupCompleted { get; set; }

    public string ReleaseTag { get; set; } = "Mach1.04166.501.CU";

    public string PreparedUtc { get; set; } = DateTime.UtcNow.ToString("O");

    public string SavedUtc { get; set; } = DateTime.UtcNow.ToString("O");
}
