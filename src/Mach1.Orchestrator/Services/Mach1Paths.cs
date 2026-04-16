using System.IO;

namespace Mach1.Orchestrator.Services;

public static class Mach1Paths
{
    public const string Brand = "Mach1 (by TAD)";

    public const string CurrentRelease = "Mach1.04166.503.BF";

    public const string GitHubOwner = "amiho-dev";

    public const string GitHubRepository = "TAD-Mach1";

    public static string Root => @"C:\Mach1";

    public static string ConfigDirectory => Path.Combine(Root, "Config");

    public static string LogDirectory => Path.Combine(Root, "Logs");

    public static string WinReDirectory => Path.Combine(Root, "WinRE");

    public static string UpdatesDirectory => Path.Combine(Root, "Updates");

    public static string WinReMountDirectory => Path.Combine(WinReDirectory, "Mount");

    public static string WinReWorkDirectory => Path.Combine(WinReDirectory, "Work");

    public static string SettingsXmlPath => Path.Combine(ConfigDirectory, "settings.xml");

    public static string PendingFlagPath => Path.Combine(ConfigDirectory, "patch.pending");

    public static string LastWinReResultPath => Path.Combine(ConfigDirectory, "last-winre-result.json");

    public static string OrchestratorLogPath => Path.Combine(LogDirectory, "mach1-orchestrator.log");

    public static string WinReLogPath => Path.Combine(LogDirectory, "mach1-winre.log");

    public static string InstalledEngineScriptPath => Path.Combine(WinReDirectory, "WinReEngine.ps1");

    public static string InstalledLogoPath => Path.Combine(ConfigDirectory, "mach1-logo.png");
}
