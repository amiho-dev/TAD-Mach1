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

        SetColor("WindowColor", light ? "#F4F7FB" : "#0F1620");
        SetColor("CardColor", light ? "#FFFFFF" : "#172230");
        SetColor("CardAltColor", light ? "#EDF3FA" : "#1C2A3B");
        SetColor("TopBandColor", light ? "#C0382B" : "#A52834");
        SetColor("AccentColor", light ? "#1276D6" : "#50A8FF");
        SetColor("AccentSoftColor", light ? "#D9EAFF" : "#1C334A");
        SetColor("TextColor", light ? "#182634" : "#E7F1FF");
        SetColor("MutedTextColor", light ? "#5D7187" : "#9FB8D3");
        SetColor("StrokeColor", light ? "#D5E0EC" : "#2E435C");
    }

    private void SetColor(string key, string hex)
    {
        Resources[key] = (Color)ColorConverter.ConvertFromString(hex);
    }
}
