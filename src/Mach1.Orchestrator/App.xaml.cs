using System.Diagnostics;
using System.Security.Principal;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace Mach1.Orchestrator;

public partial class App : Application
{
    private const string PersonalizePath = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";

    protected override void OnStartup(StartupEventArgs e)
    {
        if (!IsAdministrator())
        {
            RelaunchAsAdministrator();
            Shutdown();
            return;
        }

        ApplyThemeFromSystem();
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;

        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        base.OnExit(e);
    }

    private static bool IsAdministrator()
    {
        var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static void RelaunchAsAdministrator()
    {
        var processPath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(processPath))
        {
            MessageBox.Show("Mach1 (by TAD) could not determine the executable path for elevation.", "Mach1 (by TAD)", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        try
        {
            var psi = new ProcessStartInfo(processPath)
            {
                UseShellExecute = true,
                Verb = "runas"
            };

            Process.Start(psi);
        }
        catch
        {
            MessageBox.Show("Mach1 (by TAD) requires Administrator privileges.", "Mach1 (by TAD)", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static bool IsLightTheme()
    {
        using var key = Registry.CurrentUser.OpenSubKey(PersonalizePath);
        if (key?.GetValue("AppsUseLightTheme") is int value)
        {
            return value != 0;
        }

        return true;
    }

    private void OnUserPreferenceChanged(object? sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category is UserPreferenceCategory.General or UserPreferenceCategory.Color)
        {
            ApplyThemeFromSystem();
        }
    }

    private void ApplyThemeFromSystem()
    {
        var light = IsLightTheme();

        SetColor("WindowColor", light ? "#E9EEF4" : "#0F1620");
        SetColor("CardColor", light ? "#F9FBFD" : "#172230");
        SetColor("CardAltColor", light ? "#EEF3F8" : "#1C2A3B");
        SetColor("TopBandColor", light ? "#23415E" : "#1D2D40");
        SetColor("AccentColor", light ? "#1D5F9E" : "#50A8FF");
        SetColor("AccentSoftColor", light ? "#D8E5F2" : "#1C334A");
        SetColor("TextColor", light ? "#1A2A3A" : "#E7F1FF");
        SetColor("MutedTextColor", light ? "#556A80" : "#9FB8D3");
        SetColor("StrokeColor", light ? "#C1CDD8" : "#2E435C");
    }

    private void SetColor(string key, string hex)
    {
        Resources[key] = (Color)ColorConverter.ConvertFromString(hex);
    }
}
