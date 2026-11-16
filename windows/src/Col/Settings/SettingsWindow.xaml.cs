using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using Col.Core;
using Col.Island;
using Col.Localization;
using Col.Native;
using Col.Services;
using Col.Theme;

namespace Col.Settings;

/// <summary>
/// Col's settings: General, Music and lyrics, Agents, About. Every change applies at once, the way Windows' own
/// Settings work: there is no Save button.
/// </summary>
internal partial class SettingsWindow : Window
{
    private readonly Hub _hub;
    private bool _loading;

    public SettingsWindow(Hub hub)
    {
        InitializeComponent();
        _hub = hub;
        NavGeneral.Checked += (_, _) => ShowPage("general");
        NavMusic.Checked += (_, _) => ShowPage("music");
        NavAgents.Checked += (_, _) => ShowPage("agents");
        NavAbout.Checked += (_, _) => ShowPage("about");

        foreach (var toggle in new[] { VisibleAtRest, OpenOnHover, VolumeDisplay, BatteryDisplay, ClipboardToggle, NowPlayingToggle, LyricsToggle, LyricLineClosed })
        {
            toggle.Checked += (_, _) => Save();
            toggle.Unchecked += (_, _) => Save();
        }
        foreach (var size in new[] { SizeCompact, SizeStandard, SizeLarge }) size.Checked += (_, _) => Save();
        LaunchAtLogin.Checked += (_, _) => { if (!_loading && !_hub.IsDemo) StartupRegistration.Set(true); };
        LaunchAtLogin.Unchecked += (_, _) => { if (!_loading && !_hub.IsDemo) StartupRegistration.Set(false); };
        ClearLyrics.Click += (_, _) =>
        {
            _hub.ClearLyricsCache();
            CacheDetail.Text = CacheSize();
        };
        LinkWebsite.Click += (_, _) => Open("https://getcol.vercel.app");
        LinkSource.Click += (_, _) => Open("https://github.com/ruben4reall/col/tree/main/windows");
        LinkChangelog.Click += (_, _) => Open("https://github.com/ruben4reall/col/blob/main/CHANGELOG.md");
        LinkIssues.Click += (_, _) => Open("https://github.com/ruben4reall/col/issues");
        VersionText.Text = L.Format("About_Version", AppPaths.Version);
        Load();
        ShowPage("general");
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        ThemeManager.Decorate(this);
        HwndSource.FromHwnd(new WindowInteropHelper(this).Handle)?.AddHook(WindowProcedure);
    }

    private IntPtr WindowProcedure(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        // Light or dark, or the accent colour, changed in Windows' Settings.
        if (message is Win32.WM_SETTINGCHANGE or Win32.WM_DWMCOLORIZATIONCOLORCHANGED)
        {
            Dispatcher.BeginInvoke(() =>
            {
                ThemeManager.Apply();
                ThemeManager.Decorate(this);
            });
        }
        return IntPtr.Zero;
    }

    public void ShowPage(string? page)
    {
        page = page?.ToLowerInvariant() switch
        {
            "music" or "lyrics" => "music",
            "agents" or "developers" or "aiapps" => "agents",
            "about" => "about",
            _ => "general",
        };
        (page switch { "music" => NavMusic, "agents" => NavAgents, "about" => NavAbout, _ => NavGeneral }).IsChecked = true;
        GeneralPage.Visibility = page == "general" ? Visibility.Visible : Visibility.Collapsed;
        MusicPage.Visibility = page == "music" ? Visibility.Visible : Visibility.Collapsed;
        AgentsPage.Visibility = page == "agents" ? Visibility.Visible : Visibility.Collapsed;
        AboutPage.Visibility = page == "about" ? Visibility.Visible : Visibility.Collapsed;
        PageTitle.Text = L.Get(page switch { "music" => "Nav_Music", "agents" => "Nav_Agents", "about" => "Nav_About", _ => "Nav_General" });
        if (page == "agents") RefreshAgents();
        if (page == "music") CacheDetail.Text = CacheSize();
    }

    private void Load()
    {
        _loading = true;
        var settings = _hub.Settings;
        LaunchAtLogin.IsChecked = !_hub.IsDemo ? StartupRegistration.IsOn : true;
        VisibleAtRest.IsChecked = settings.VisibleAtRest;
        OpenOnHover.IsChecked = settings.OpenOnHover;
        VolumeDisplay.IsChecked = settings.VolumeDisplay;
        BatteryDisplay.IsChecked = settings.BatteryDisplay;
        ClipboardToggle.IsChecked = settings.ClipboardHistory;
        NowPlayingToggle.IsChecked = settings.NowPlaying;
        LyricsToggle.IsChecked = settings.Lyrics;
        LyricLineClosed.IsChecked = settings.LyricLineClosed;
        SizeCompact.IsChecked = settings.Size == IslandSize.Compact;
        SizeStandard.IsChecked = settings.Size == IslandSize.Standard;
        SizeLarge.IsChecked = settings.Size == IslandSize.Large;
        BuildMonitors(settings.Monitor);
        _loading = false;
    }

    private void BuildMonitors(string chosen)
    {
        MonitorChoices.Children.Clear();
        var monitors = Monitors.All();
        var primary = new RadioButton
        {
            Style = (Style)FindResource("Win.Radio"), GroupName = "Monitor", Tag = "primary",
            Content = L.Get("General_Display_Primary"),
            IsChecked = string.Equals(chosen, "primary", StringComparison.OrdinalIgnoreCase) || monitors.All(m => m.Device != chosen),
        };
        primary.Checked += (_, _) => Save();
        MonitorChoices.Children.Add(primary);
        foreach (var monitor in monitors)
        {
            var label = L.Format("General_Display_Number", monitor.Number, monitor.Bounds.Width, monitor.Bounds.Height);
            if (monitor.IsPrimary) label += "  ·  " + L.Get("General_Display_IsPrimary");
            var choice = new RadioButton
            {
                Style = (Style)FindResource("Win.Radio"), GroupName = "Monitor", Tag = monitor.Device, Content = label,
                IsChecked = string.Equals(monitor.Device, chosen, StringComparison.OrdinalIgnoreCase),
            };
            choice.Checked += (_, _) => Save();
            MonitorChoices.Children.Add(choice);
        }
    }

    private void Save()
    {
        if (_loading) return;
        var settings = _hub.Settings.Copy();
        settings.VisibleAtRest = VisibleAtRest.IsChecked == true;
        settings.OpenOnHover = OpenOnHover.IsChecked == true;
        settings.VolumeDisplay = VolumeDisplay.IsChecked == true;
        settings.BatteryDisplay = BatteryDisplay.IsChecked == true;
        settings.ClipboardHistory = ClipboardToggle.IsChecked == true;
        settings.NowPlaying = NowPlayingToggle.IsChecked == true;
        settings.Lyrics = LyricsToggle.IsChecked == true;
        settings.LyricLineClosed = LyricLineClosed.IsChecked == true;
        settings.Size = SizeCompact.IsChecked == true ? IslandSize.Compact : SizeLarge.IsChecked == true ? IslandSize.Large : IslandSize.Standard;
        settings.Monitor = MonitorChoices.Children.OfType<RadioButton>().FirstOrDefault(r => r.IsChecked == true)?.Tag as string ?? "primary";
        _hub.Apply(settings);
    }

    // Agents.

    private void RefreshAgents()
    {
        AgentCards.Children.Clear();
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var colctl = AppPaths.Colctl;
        var haveColctl = File.Exists(colctl) || _hub.IsDemo;
        ColctlPath.Text = haveColctl ? L.Format("Agents_Colctl_Path", colctl) : L.Get("Agents_Colctl_Missing");
        foreach (var agent in HooksInstaller.All) AgentCards.Children.Add(AgentCard(agent, home, colctl, haveColctl));
        var note = new TextBlock { Style = (Style)FindResource("Win.CardDetail"), Text = L.Get("Agents_Backup"), Margin = new Thickness(1, 6, 0, 0) };
        AgentCards.Children.Add(note);
    }

    private FrameworkElement AgentCard(HookAgent agent, string home, string colctl, bool haveColctl)
    {
        var path = agent.SettingsPath(home);
        var connected = _hub.IsDemo ? agent.Agent == CodingAgent.Claude : HooksInstaller.IsConnected(path);
        var installed = _hub.IsDemo || HooksInstaller.IsInstalled(agent, home);
        var card = new Border { Style = (Style)FindResource("Win.Card") };
        var dock = new DockPanel();
        var logo = CompactViews.AgentLogo(agent.Name, 28);
        logo.Margin = new Thickness(0, 0, 14, 0);
        logo.VerticalAlignment = VerticalAlignment.Center;
        dock.Children.Add(logo);
        var button = new Button
        {
            Style = (Style)FindResource(connected ? "Win.Button" : "Win.AccentButton"),
            Content = L.Get(connected ? "Agents_Disconnect" : "Agents_Connect"),
            IsEnabled = haveColctl,
        };
        button.Click += (_, _) => Connect(agent, path, colctl, !connected);
        DockPanel.SetDock(button, Dock.Right);
        dock.Children.Add(button);
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(new TextBlock { Style = (Style)FindResource("Win.CardTitle"), Text = agent.Name });
        var status = new TextBlock { Style = (Style)FindResource("Win.CardDetail") };
        if (connected)
        {
            status.Text = L.Get("Agents_Connected");
            status.SetResourceReference(TextBlock.ForegroundProperty, "Win.Success");
        }
        else
        {
            status.Text = L.Get(installed ? "Agents_NotConnected" : "Agents_NotFound");
        }
        texts.Children.Add(status);
        texts.Children.Add(new TextBlock { Style = (Style)FindResource("Win.CardDetail"), Text = path, Opacity = 0.8 });
        dock.Children.Add(texts);
        card.Child = dock;
        return card;
    }

    private void Connect(HookAgent agent, string path, string colctl, bool install)
    {
        if (_hub.IsDemo) return;
        try
        {
            HooksInstaller.Edit(agent, path, install, colctl);
        }
        catch (HooksException error)
        {
            MessageBox.Show(this, error.Message, "Col", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        RefreshAgents();
    }

    // Music.

    private static string CacheSize()
    {
        try
        {
            var folder = new DirectoryInfo(AppPaths.Lyrics);
            var files = folder.Exists ? folder.GetFiles("*.json") : [];
            var bytes = files.Sum(f => f.Length);
            return L.Format("Music_Cache_Detail", files.Length, Math.Max(1, (int)Math.Ceiling(bytes / 1024.0)));
        }
        catch (Exception)
        {
            return "";
        }
    }

    private static void Open(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch (Exception error)
        {
            Log.Write("open link: " + error.Message);
        }
    }
}
