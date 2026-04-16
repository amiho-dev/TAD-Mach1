namespace Mach1.Orchestrator.Models;

public sealed class Mach1Settings
{
    public bool KernelTimerTweaks { get; set; }

    public bool ServiceHardening { get; set; }

    public bool Cs2PerformancePack { get; set; }

    public bool VerboseMode { get; set; }

    public bool BackupToggleConfirmed { get; set; }

    public bool BackupCompleted { get; set; }

    public string ReleaseTag { get; set; } = "Mach1.0416.500.BF";

    public string SavedUtc { get; set; } = DateTime.UtcNow.ToString("O");
}
