namespace Mach1.Orchestrator.Models;

public sealed class Mach1Settings
{
    public string SessionId { get; set; } = Guid.NewGuid().ToString("N");

    public string OptimizationProfile { get; set; } = "Recommended";

    public bool KernelTimerTweaks { get; set; }

    public bool ServiceHardening { get; set; }

    public bool Cs2PerformancePack { get; set; }

    public bool VerboseMode { get; set; }

    public bool BackupToggleConfirmed { get; set; }

    public bool BackupCompleted { get; set; }

    public bool BackupBypassConfirmed { get; set; }

    public string HostProductName { get; set; } = string.Empty;

    public int HostBuild { get; set; }

    public string ReleaseTag { get; set; } = "Mach1.04166.503.BF";

    public string PreparedUtc { get; set; } = DateTime.UtcNow.ToString("O");

    public string SavedUtc { get; set; } = DateTime.UtcNow.ToString("O");
}
