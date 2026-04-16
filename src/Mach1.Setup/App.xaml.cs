using System.Diagnostics;
using System.Security.Principal;
using System.Windows;

namespace Mach1.Setup;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        if (!IsAdministrator())
        {
            RelaunchAsAdministrator();
            Shutdown();
            return;
        }

        base.OnStartup(e);
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
            MessageBox.Show("Mach1 setup could not determine executable path for elevation.", "Mach1 Setup", MessageBoxButton.OK, MessageBoxImage.Error);
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
            MessageBox.Show("Mach1 setup requires Administrator privileges.", "Mach1 Setup", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
