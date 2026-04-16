using System.IO;
using System.Text.Json;
using Mach1.Orchestrator.Models;

namespace Mach1.Orchestrator.Services;

public sealed class BridgeService
{
    private readonly LogService _logService;

    public BridgeService(LogService logService)
    {
        _logService = logService;
    }

    public WinReBridgeResult? ReadLastResult()
    {
        try
        {
            if (!File.Exists(Mach1Paths.LastWinReResultPath))
            {
                return null;
            }

            var json = File.ReadAllText(Mach1Paths.LastWinReResultPath);
            return JsonSerializer.Deserialize<WinReBridgeResult>(json);
        }
        catch (Exception ex)
        {
            _logService.Warn($"Failed to parse WinRE bridge result: {ex.Message}");
            return null;
        }
    }
}
