using System.IO;
using System.Xml.Serialization;
using Mach1.Orchestrator.Models;

namespace Mach1.Orchestrator.Services;

public sealed class SettingsService
{
    private readonly LogService _logService;

    public SettingsService(LogService logService)
    {
        _logService = logService;
    }

    public Mach1Settings LoadOrDefault()
    {
        try
        {
            if (!File.Exists(Mach1Paths.SettingsXmlPath))
            {
                return new Mach1Settings { ReleaseTag = Mach1Paths.CurrentRelease };
            }

            using var fs = File.OpenRead(Mach1Paths.SettingsXmlPath);
            var serializer = new XmlSerializer(typeof(Mach1Settings));
            var loaded = serializer.Deserialize(fs) as Mach1Settings;

            if (loaded is null)
            {
                return new Mach1Settings { ReleaseTag = Mach1Paths.CurrentRelease };
            }

            if (string.IsNullOrWhiteSpace(loaded.SessionId))
            {
                loaded.SessionId = Guid.NewGuid().ToString("N");
            }

            if (string.IsNullOrWhiteSpace(loaded.PreparedUtc))
            {
                loaded.PreparedUtc = DateTime.UtcNow.ToString("O");
            }

            if (string.IsNullOrWhiteSpace(loaded.OptimizationProfile))
            {
                loaded.OptimizationProfile = "Recommended";
            }

            loaded.ReleaseTag = Mach1Paths.CurrentRelease;

            return loaded;
        }
        catch (Exception ex)
        {
            _logService.Warn($"Could not load settings.xml, using defaults. {ex.Message}");
            return new Mach1Settings { ReleaseTag = Mach1Paths.CurrentRelease };
        }
    }

    public void Save(Mach1Settings settings)
    {
        settings.SavedUtc = DateTime.UtcNow.ToString("O");
        settings.PreparedUtc = string.IsNullOrWhiteSpace(settings.PreparedUtc) ? DateTime.UtcNow.ToString("O") : settings.PreparedUtc;
        settings.SessionId = string.IsNullOrWhiteSpace(settings.SessionId) ? Guid.NewGuid().ToString("N") : settings.SessionId;
        settings.OptimizationProfile = string.IsNullOrWhiteSpace(settings.OptimizationProfile) ? "Recommended" : settings.OptimizationProfile;
        settings.ReleaseTag = string.IsNullOrWhiteSpace(settings.ReleaseTag) ? Mach1Paths.CurrentRelease : settings.ReleaseTag;

        Directory.CreateDirectory(Mach1Paths.ConfigDirectory);

        using var fs = File.Create(Mach1Paths.SettingsXmlPath);
        var serializer = new XmlSerializer(typeof(Mach1Settings));
        serializer.Serialize(fs, settings);

        _logService.Info("settings.xml saved for WinRE stage consumption.");
    }
}
