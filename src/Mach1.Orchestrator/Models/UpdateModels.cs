namespace Mach1.Orchestrator.Models;

public sealed record UpdatePackage(
    string Tag,
    string ReleaseUrl,
    string? AssetName,
    string? AssetDownloadUrl);

public sealed record UpdateCheckResult(bool Success, bool IsUpdateAvailable, string Message, UpdatePackage? Package)
{
    public static UpdateCheckResult Failed(string message) => new(false, false, message, null);

    public static UpdateCheckResult UpToDate(string currentVersion) =>
        new(true, false, $"Mach1 is up to date ({currentVersion}).", null);

    public static UpdateCheckResult UpdateAvailable(UpdatePackage package) =>
        new(true, true, $"New release detected: {package.Tag}", package);
}

public sealed record UpdateDownloadResult(bool Success, bool InstallerLaunched, string Message, string? LocalPath)
{
    public static UpdateDownloadResult Failed(string message) => new(false, false, message, null);

    public static UpdateDownloadResult Skipped(string message) => new(true, false, message, null);

    public static UpdateDownloadResult Downloaded(string localPath) =>
        new(true, false, $"Update downloaded to {localPath}", localPath);

    public static UpdateDownloadResult DownloadedAndLaunched(string localPath) =>
        new(true, true, $"Update downloaded and installer launched: {localPath}", localPath);
}
