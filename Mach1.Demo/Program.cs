using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Mach1.Demo;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new DemoWindow(OsProfile.Detect()));
    }
}

internal sealed class DemoWindow : Form
{
    private const string Brand = "Mach1 (by TAD)";
    private const string Release = "M1.0415.001.BF";

    private readonly OsProfile _profile;

    // Theme Colors
    private Color _bgColor;
    private Color _fgColor;
    private Color _panelColor;
    private Color _accentColor;
    private bool _isWinRe;
    private bool _isDarkMode;

    // UI Controls
    private Panel _pnlHeader = new();
    private Label _lblTitle = new();
    private Label _lblRelease = new();
    private Label _lblOsInfo = new();
    
    private Panel _pnlMain = new();
    
    // Stages section
    private Panel _pnlStages = new();
    private Label _lblStagesTitle = new();
    private RadioButton _rbStage1 = new();
    private RadioButton _rbStage2 = new();
    private RadioButton _rbStage3 = new();
    
    // Custom Checkbox
    private CheckBox _chkCustomMode = new();
    private Panel _pnlCustomOptions = new();
    private CheckBox _chkKernel = new();
    private CheckBox _chkServices = new();
    private CheckBox _chkGame = new();
    private CheckBox _chkConsumer = new();
    private CheckBox _chkBackup = new();
    private CheckBox _chkReboot = new();

    // Plan section
    private Panel _pnlPlan = new();
    private Label _lblPlanTitle = new();
    private ListBox _lstPlan = new();
    private Button _btnPreview = new();
    private Button _btnStart = new();

    public DemoWindow(OsProfile profile)
    {
        _profile = profile;

        DetectTheme();
        InitializeComponent();
        ApplyThemeStyles();
        UpdatePlanView();
    }

    private void DetectTheme()
    {
        _isWinRe = Registry.LocalMachine.OpenSubKey(@"System\CurrentControlSet\Control\MiniNT") != null;
        
        _isDarkMode = false;
        if (!_isWinRe)
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                if (key != null)
                {
                    var lightTheme = key.GetValue("AppsUseLightTheme") as int?;
                    if (lightTheme.HasValue && lightTheme.Value == 0)
                    {
                        _isDarkMode = true;
                    }
                }
            }
            catch { }
        }

        if (_isWinRe)
        {
            _bgColor = Color.White;
            _fgColor = Color.Black;
            _panelColor = Color.FromArgb(240, 240, 240);
            _accentColor = Color.Black;
        }
        else if (_isDarkMode)
        {
            _bgColor = Color.FromArgb(18, 18, 18);
            _fgColor = Color.White;
            _panelColor = Color.FromArgb(30, 30, 30);
            _accentColor = Color.White;
        }
        else // Light Mode
        {
            _bgColor = Color.White;
            _fgColor = Color.Black;
            _panelColor = Color.FromArgb(245, 245, 245);
            _accentColor = Color.Black;
        }
    }

    private void InitializeComponent()
    {
        Text = $"{Brand} - Demo";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(800, 600);
        Size = new Size(850, 650);
        Font = new Font("Segoe UI", 10F, FontStyle.Regular, GraphicsUnit.Point);

        // -- Header --
        _pnlHeader.Dock = DockStyle.Top;
        _pnlHeader.Height = 100;
        _pnlHeader.Padding = new Padding(20);

        var picLogo = new PictureBox
        {
            Size = new Size(60, 60),
            SizeMode = PictureBoxSizeMode.Zoom,
            Location = new Point(20, 20)
        };
        var bmp = LoadLogoImage();
        if (bmp != null) picLogo.Image = bmp;
        _pnlHeader.Controls.Add(picLogo);

        _lblTitle.Text = "Mach1 Demo";
        _lblTitle.Font = new Font("Segoe UI", 18F, FontStyle.Bold);
        _lblTitle.Location = new Point(90, 20);
        _lblTitle.AutoSize = true;

        _lblOsInfo.Text = $"{_profile.ProductName} ({_profile.Edition}) Build {_profile.BuildNumber}\nProfile: {_profile.ProfileName}";
        _lblOsInfo.Location = new Point(90, 55);
        _lblOsInfo.AutoSize = true;

        _lblRelease.Text = Release;
        _lblRelease.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _lblRelease.TextAlign = ContentAlignment.TopRight;
        _lblRelease.Location = new Point(ClientSize.Width - 150, 20);
        _lblRelease.Size = new Size(130, 20);

        _pnlHeader.Controls.Add(_lblTitle);
        _pnlHeader.Controls.Add(_lblOsInfo);
        _pnlHeader.Controls.Add(_lblRelease);
        
        // -- Main Layout --
        _pnlMain.Dock = DockStyle.Fill;
        _pnlMain.Padding = new Padding(20);

        var table = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 55F));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 45F));
        
        // -- Stages / left panel --
        _pnlStages.Dock = DockStyle.Fill;
        _pnlStages.Margin = new Padding(0, 0, 10, 0);

        _lblStagesTitle.Text = "Execution Profile";
        _lblStagesTitle.Font = new Font("Segoe UI", 12F, FontStyle.Bold);
        _lblStagesTitle.Location = new Point(10, 10);
        _lblStagesTitle.AutoSize = true;

        _rbStage1.Text = "Stage 1 - Baseline\n(Core stability and game profile)";
        _rbStage1.Location = new Point(15, 45);
        _rbStage1.AutoSize = true;
        _rbStage1.Checked = true;
        
        _rbStage2.Text = "Stage 2 - Performance\n(Baseline + Adaptive Appx/Copilot cleanup)";
        _rbStage2.Location = new Point(15, 95);
        _rbStage2.AutoSize = true;

        _rbStage3.Text = "Stage 3 - Recovery Ready\n(Performance + Backup/Reboot flow)";
        _rbStage3.Location = new Point(15, 145);
        _rbStage3.AutoSize = true;

        _chkCustomMode.Text = "Custom Mode (No Warranty)";
        _chkCustomMode.Location = new Point(15, 210);
        _chkCustomMode.AutoSize = true;
        _chkCustomMode.Font = new Font("Segoe UI", 10F, FontStyle.Bold);

        // Custom Options panel
        _pnlCustomOptions.Location = new Point(35, 240);
        _pnlCustomOptions.Size = new Size(350, 200);
        _pnlCustomOptions.Enabled = false;

        _chkKernel.Text = "Kernel/Timer"; _chkKernel.Location = new Point(0, 0); _chkKernel.AutoSize = true;
        _chkServices.Text = "Service Hardening"; _chkServices.Location = new Point(0, 30); _chkServices.AutoSize = true;
        _chkGame.Text = "Game Optimization"; _chkGame.Location = new Point(0, 60); _chkGame.AutoSize = true;
        _chkConsumer.Text = "Consumer Cleanup"; _chkConsumer.Location = new Point(0, 90); _chkConsumer.AutoSize = true;
        _chkBackup.Text = "Backup Flow"; _chkBackup.Location = new Point(0, 120); _chkBackup.AutoSize = true;
        _chkReboot.Text = "Reboot Flow"; _chkReboot.Location = new Point(0, 150); _chkReboot.AutoSize = true;

        if (!_profile.ShouldApplyConsumerCleanup)
        {
            _chkConsumer.Enabled = false;
            _chkConsumer.Text += " (Unavailable)";
        }

        _pnlCustomOptions.Controls.AddRange(new Control[] { _chkKernel, _chkServices, _chkGame, _chkConsumer, _chkBackup, _chkReboot });

        _pnlStages.Controls.AddRange(new Control[] { 
            _lblStagesTitle, _rbStage1, _rbStage2, _rbStage3, 
            _chkCustomMode, _pnlCustomOptions 
        });

        // -- Plan / right panel --
        _pnlPlan.Dock = DockStyle.Fill;
        _pnlPlan.Margin = new Padding(10, 0, 0, 0);

        _lblPlanTitle.Text = "Plan Actions";
        _lblPlanTitle.Font = new Font("Segoe UI", 12F, FontStyle.Bold);
        _lblPlanTitle.Location = new Point(10, 10);
        _lblPlanTitle.AutoSize = true;

        _lstPlan.Location = new Point(10, 45);
        _lstPlan.Size = new Size(300, 280);
        _lstPlan.IntegralHeight = false;
        
        _btnPreview.Text = "Preview";
        _btnPreview.Location = new Point(10, 340);
        _btnPreview.Size = new Size(140, 35);
        _btnPreview.FlatStyle = FlatStyle.Flat;

        _btnStart.Text = "Start";
        _btnStart.Location = new Point(170, 340);
        _btnStart.Size = new Size(140, 35);
        _btnStart.FlatStyle = FlatStyle.Flat;

        _pnlPlan.Controls.AddRange(new Control[] { _lblPlanTitle, _lstPlan, _btnPreview, _btnStart });

        table.Controls.Add(_pnlStages, 0, 0);
        table.Controls.Add(_pnlPlan, 1, 0);
        _pnlMain.Controls.Add(table);

        Controls.Add(_pnlMain);
        Controls.Add(_pnlHeader);

        // Events
        _rbStage1.CheckedChanged += (s, e) => UpdatePlanView();
        _rbStage2.CheckedChanged += (s, e) => UpdatePlanView();
        _rbStage3.CheckedChanged += (s, e) => UpdatePlanView();

        _chkCustomMode.CheckedChanged += (s, e) => 
        {
            _pnlCustomOptions.Enabled = _chkCustomMode.Checked;
            if (_chkCustomMode.Checked)
            {
                _rbStage1.Checked = false;
                _rbStage2.Checked = false;
                _rbStage3.Checked = false;
                _lblPlanTitle.Text = "Custom Actions (No Warranty)";
            }
            else
            {
                _rbStage1.Checked = true;
                _lblPlanTitle.Text = "Plan Actions";
            }
            UpdatePlanView();
        };

        foreach (Control c in _pnlCustomOptions.Controls)
        {
            if (c is CheckBox cb) cb.CheckedChanged += (s, e) => UpdatePlanView();
        }

        _btnPreview.Click += (s, e) => MessageBox.Show("Preview only available in full release.", "Preview", MessageBoxButtons.OK, MessageBoxIcon.Information);
        _btnStart.Click += (s, e) => MessageBox.Show("Demo limitations prevent execution.", "Demo Locked", MessageBoxButtons.OK, MessageBoxIcon.Stop);
    }

    private void ApplyThemeStyles()
    {
        BackColor = _bgColor;
        ForeColor = _fgColor;

        _pnlHeader.BackColor = _panelColor;
        _pnlStages.BackColor = _bgColor;
        _pnlPlan.BackColor = _bgColor;

        _lstPlan.BackColor = _panelColor;
        _lstPlan.ForeColor = _fgColor;
        _lstPlan.BorderStyle = _isWinRe ? BorderStyle.Fixed3D : BorderStyle.FixedSingle;

        void StyleButton(Button btn, bool primary)
        {
            btn.BackColor = primary ? _accentColor : _panelColor;
            btn.ForeColor = primary ? _bgColor : _fgColor;
            btn.FlatAppearance.BorderColor = primary ? _accentColor : _fgColor;
            
            if (_isWinRe) btn.FlatStyle = FlatStyle.Standard; 
        }

        StyleButton(_btnStart, true);
        StyleButton(_btnPreview, false);

        if (_isDarkMode)
        {
            _btnStart.ForeColor = Color.Black; 
        }
    }

    private void UpdatePlanView()
    {
        _lstPlan.Items.Clear();

        if (_chkCustomMode.Checked)
        {
            if (_chkKernel.Checked) _lstPlan.Items.Add("Kernel/Timer");
            if (_chkServices.Checked) _lstPlan.Items.Add("Service Hardening");
            if (_chkGame.Checked) _lstPlan.Items.Add("Game Optimization");
            if (_chkConsumer.Checked && _profile.ShouldApplyConsumerCleanup) _lstPlan.Items.Add("Consumer Cleanup");
            if (_chkBackup.Checked) _lstPlan.Items.Add("Backup Flow");
            if (_chkReboot.Checked) _lstPlan.Items.Add("Reboot Flow");
        }
        else
        {
            _lstPlan.Items.Add("Kernel/Timer");
            _lstPlan.Items.Add("Service Hardening");
            _lstPlan.Items.Add("Game Optimization");

            if (_rbStage2.Checked || _rbStage3.Checked)
            {
                if (_profile.ShouldApplyConsumerCleanup) _lstPlan.Items.Add("Consumer Cleanup");
            }

            if (_rbStage3.Checked)
            {
                _lstPlan.Items.Add("Backup Flow");
                _lstPlan.Items.Add("Reboot Flow");
            }
        }
        
        if (_lstPlan.Items.Count == 0)
        {
            _lstPlan.Items.Add("(No modules selected)");
        }
    }

    private Image? LoadLogoImage()
    {
        try
        {
            var assembly = typeof(DemoWindow).Assembly;
            using var stream = assembly.GetManifestResourceStream("Mach1Logo");
            if (stream != null)
            {
                return Image.FromStream(stream);
            }
        }
        catch { }
        return null;
    }
}

internal sealed class OsProfile
{
    public OsProfile(string productName, string edition, string buildNumber, bool isWindows11, bool isLtsc)
    {
        ProductName = string.IsNullOrWhiteSpace(productName) ? "Unknown Windows" : productName;
        Edition = string.IsNullOrWhiteSpace(edition) ? "Unknown" : edition;
        BuildNumber = string.IsNullOrWhiteSpace(buildNumber) ? "Unknown" : buildNumber;
        IsWindows11 = isWindows11;
        IsLtsc = isLtsc;
    }

    public string ProductName { get; }
    public string Edition { get; }
    public string BuildNumber { get; }
    public bool IsWindows11 { get; }
    public bool IsLtsc { get; }

    public bool ShouldApplyConsumerCleanup => IsWindows11 && !IsLtsc;

    public string ProfileName
    {
        get
        {
            if (IsLtsc) return "LTSC";
            if (IsWindows11) return "Windows 11 Standard";
            return "Baseline";
        }
    }

    public static OsProfile Detect()
    {
        var productName = Environment.OSVersion.VersionString;
        var edition = "Unknown";
        var build = Environment.OSVersion.Version.Build.ToString();

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            try
            {
                using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
                if (key != null)
                {
                    var registryProduct = key.GetValue("ProductName") as string;
                    var registryEdition = key.GetValue("EditionID") as string;
                    var registryBuild = key.GetValue("CurrentBuildNumber") as string;

                    if (!string.IsNullOrWhiteSpace(registryProduct)) productName = registryProduct.Trim();
                    if (!string.IsNullOrWhiteSpace(registryEdition)) edition = registryEdition.Trim();
                    if (!string.IsNullOrWhiteSpace(registryBuild)) build = registryBuild.Trim();
                }
            }
            catch { }
        }

        var parsedBuild = 0;
        int.TryParse(build, out parsedBuild);
        
        var isWindows11 = productName.Contains("Windows 11", StringComparison.OrdinalIgnoreCase) || parsedBuild >= 22000;
        var isLtsc =
            edition.Contains("LTSC", StringComparison.OrdinalIgnoreCase) ||
            edition.Contains("EnterpriseS", StringComparison.OrdinalIgnoreCase) ||
            edition.Contains("IoTEnterpriseS", StringComparison.OrdinalIgnoreCase) ||
            productName.Contains("LTSC", StringComparison.OrdinalIgnoreCase);

        return new OsProfile(productName, edition, build, isWindows11, isLtsc);
    }
}
