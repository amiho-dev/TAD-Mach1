namespace Mach1.Orchestrator.Models;

public sealed class WinReBridgeResult
{
    public string SessionId { get; set; } = string.Empty;

    public string ReleaseTag { get; set; } = string.Empty;

    public bool Success { get; set; }

    public string Message { get; set; } = string.Empty;

    public string CompletedUtc { get; set; } = DateTime.UtcNow.ToString("O");
}
