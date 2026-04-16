using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Mach1.Orchestrator.Models;

namespace Mach1.Orchestrator.Services;

public sealed class UpdaterService
{
    private static readonly HttpClient HttpClient = BuildClient();
    private readonly LogService _logService;

    public UpdaterService(LogService logService)
    {
        _logService = logService;
    }

    public async Task<UpdateCheckResult> CheckForUpdatesAsync(CancellationToken cancellationToken = default)
    {
        var latestUrl = $"https://api.github.com/repos/{Mach1Paths.GitHubOwner}/{Mach1Paths.GitHubRepository}/releases/latest";

        try
        {
            using var response = await HttpClient.GetAsync(latestUrl, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return UpdateCheckResult.Failed($"GitHub API returned {(int)response.StatusCode}.");
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            var release = await JsonSerializer.DeserializeAsync<GitHubReleaseResponse>(stream, cancellationToken: cancellationToken).ConfigureAwait(false);

            if (release is null || string.IsNullOrWhiteSpace(release.TagName))
            {
                return UpdateCheckResult.Failed("GitHub returned invalid release metadata.");
            }

            var current = Mach1Paths.CurrentRelease;
            if (!IsNewerVersion(current, release.TagName))
            {
                return UpdateCheckResult.UpToDate(current);
            }

            var asset = release.Assets
                .Where(a => !string.IsNullOrWhiteSpace(a.DownloadUrl) && !string.IsNullOrWhiteSpace(a.Name))
                .OrderByDescending(a => a.Name!.Contains("Mach1.Setup", StringComparison.OrdinalIgnoreCase))
                .ThenByDescending(a => a.Name!.EndsWith(".msi", StringComparison.OrdinalIgnoreCase) || a.Name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                .ThenBy(a => a.Name, StringComparer.OrdinalIgnoreCase)
                .FirstOrDefault();
            return UpdateCheckResult.UpdateAvailable(new UpdatePackage(
                release.TagName,
                release.HtmlUrl ?? string.Empty,
                asset?.Name,
                asset?.DownloadUrl));
        }
        catch (Exception ex)
        {
            _logService.Warn($"Update check failed: {ex.Message}");
            return UpdateCheckResult.Failed($"Update check failed: {ex.Message}");
        }
    }

    public async Task<UpdateDownloadResult> DownloadAndStageAsync(UpdatePackage package, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(package.AssetDownloadUrl) || string.IsNullOrWhiteSpace(package.AssetName))
        {
            return UpdateDownloadResult.Skipped("No downloadable asset found in latest release.");
        }

        try
        {
            Directory.CreateDirectory(Mach1Paths.UpdatesDirectory);
            var localPath = Path.Combine(Mach1Paths.UpdatesDirectory, package.AssetName);

            using var response = await HttpClient.GetAsync(package.AssetDownloadUrl, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return UpdateDownloadResult.Failed($"Asset download failed with {(int)response.StatusCode}.");
            }

            await using (var inStream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false))
            await using (var outStream = File.Create(localPath))
            {
                await inStream.CopyToAsync(outStream, cancellationToken).ConfigureAwait(false);
            }

            _logService.Info($"Update asset downloaded to {localPath}");

            var launched = TryLaunchInstaller(localPath);
            return launched
                ? UpdateDownloadResult.DownloadedAndLaunched(localPath)
                : UpdateDownloadResult.Downloaded(localPath);
        }
        catch (Exception ex)
        {
            _logService.Warn($"Update download failed: {ex.Message}");
            return UpdateDownloadResult.Failed($"Update download failed: {ex.Message}");
        }
    }

    private static bool TryLaunchInstaller(string filePath)
    {
        var extension = Path.GetExtension(filePath).ToLowerInvariant();
        if (extension != ".msi" && extension != ".exe")
        {
            return false;
        }

        var psi = new ProcessStartInfo(filePath)
        {
            UseShellExecute = true,
            Verb = "runas"
        };

        if (extension == ".exe")
        {
            psi.Arguments = "-update";
        }

        Process.Start(psi);
        return true;
    }

    private static bool IsNewerVersion(string current, string remote)
    {
        if (TryParseVersion(current, out var currentVersion) && TryParseVersion(remote, out var remoteVersion))
        {
            return remoteVersion > currentVersion;
        }

        return !string.Equals(current, remote, StringComparison.OrdinalIgnoreCase);
    }

    private static bool TryParseVersion(string value, out ComparableVersion version)
    {
        var match = Regex.Match(value.Trim(), "^(?:Mach1|M1)\\.(\\d{4,5})\\.(\\d{3})\\.([A-Za-z0-9]+)$", RegexOptions.IgnoreCase);
        if (!match.Success)
        {
            version = default;
            return false;
        }

        var mmdd = int.Parse(match.Groups[1].Value);
        var seq = int.Parse(match.Groups[2].Value);
        var suffix = match.Groups[3].Value.ToUpperInvariant();

        version = new ComparableVersion(mmdd, seq, suffix);
        return true;
    }

    private static HttpClient BuildClient()
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Mach1-Orchestrator-Updater");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    private readonly record struct ComparableVersion(int Mmdd, int Sequence, string Suffix) : IComparable<ComparableVersion>
    {
        public int CompareTo(ComparableVersion other)
        {
            var mmddCompare = Mmdd.CompareTo(other.Mmdd);
            if (mmddCompare != 0)
            {
                return mmddCompare;
            }

            var seqCompare = Sequence.CompareTo(other.Sequence);
            if (seqCompare != 0)
            {
                return seqCompare;
            }

            return string.Compare(Suffix, other.Suffix, StringComparison.OrdinalIgnoreCase);
        }

        public static bool operator >(ComparableVersion left, ComparableVersion right) => left.CompareTo(right) > 0;
        public static bool operator <(ComparableVersion left, ComparableVersion right) => left.CompareTo(right) < 0;
    }

    private sealed class GitHubReleaseResponse
    {
        [JsonPropertyName("tag_name")]
        public string TagName { get; init; } = string.Empty;

        [JsonPropertyName("html_url")]
        public string? HtmlUrl { get; init; }

        [JsonPropertyName("assets")]
        public List<GitHubAssetResponse> Assets { get; init; } = new();
    }

    private sealed class GitHubAssetResponse
    {
        [JsonPropertyName("name")]
        public string? Name { get; init; }

        [JsonPropertyName("browser_download_url")]
        public string? DownloadUrl { get; init; }
    }
}
