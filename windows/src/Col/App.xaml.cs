using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Security.Principal;
using System.Windows;
using System.Windows.Threading;
using Col.Core;
using Col.Island;
using Col.Localization;
using Col.Native;
using Col.Services;
using Col.Settings;
using Col.Theme;

namespace Col;

/// <summary>What Col was started with.</summary>
internal sealed record Options(DemoState? Demo, string? Language, bool Background, bool OpenSettings, string? Page, string? Link)
{
    /// <summary>
    /// <c>--demo &lt;state&gt;</c> (collapsed, peek, music, lyrics, agent-permission, agents, live, volume, battery, timer,
    /// tools, settings), <c>--lang fr</c>, <c>--background</c> at login, <c>--settings [page]</c>, <c>--page</c>, and
    /// a <c>col://</c> link, which Windows passes when one is opened.
    /// </summary>
    public static Options Parse(string[] arguments)
    {
        DemoState? demo = null;
        string? language = null, page = null, link = null;
        bool background = false, settings = false;
        for (var index = 0; index < arguments.Length; index++)
        {
            var argument = arguments[index];
            string? Next() => index + 1 < arguments.Length && !arguments[index + 1].StartsWith("--", StringComparison.Ordinal) ? arguments[++index] : null;
            switch (argument.ToLowerInvariant())
            {
                case "--demo": demo = Core.Demo.Parse(Next()); break;
                case "--lang": language = Next(); break;
                case "--background": background = true; break;
                case "--settings": settings = true; page = Next() ?? page; break;
                case "--page": page = Next(); break;
                default:
                    if (argument.StartsWith("col://", StringComparison.OrdinalIgnoreCase)) link = argument;
                    break;
            }
        }
        return new Options(demo, language, background, settings, page, link);
    }
}

internal partial class App : Application
{
    private Mutex? _single;
    private Hub? _hub;
    private IslandWindow? _island;
    private SettingsWindow? _settings;
    private TrayIcon? _tray;
    private PipeServer? _pipe;
    private MediaService? _media;
    private VolumeWatcher? _volume;
    private bool _quitting;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var options = Options.Parse(e.Args);
        if (options.Language is { Length: > 0 } language)
        {
            try
            {
                var culture = CultureInfo.GetCultureInfo(language);
                CultureInfo.DefaultThreadCurrentUICulture = culture;
                CultureInfo.CurrentUICulture = culture;
            }
            catch (CultureNotFoundException)
            {
            }
        }
        DispatcherUnhandledException += (_, args) =>
        {
            Log.Write("error: " + args.Exception);
            args.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, args) => Log.Write("fatal: " + args.ExceptionObject);
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            Log.Write("task: " + args.Exception.Message);
            args.SetObserved();
        };

        if (options.Demo is null)
        {
            // One island: a second Col hands its link, or its wish to show the settings, to the one running, and quits.
            using var identity = WindowsIdentity.GetCurrent();
            _single = new Mutex(true, "Local\\Col-" + (identity.User?.Value ?? "user"), out var first);
            if (!first)
            {
                if (!options.Background) HandOver(options.Link ?? "col://settings" + (options.Page is { } p ? "?pane=" + p : ""));
                _single.Dispose();
                _single = null;
                Shutdown();
                return;
            }
        }

        var firstLaunch = options.Demo is null && !File.Exists(AppPaths.Settings);
        var settings = options.Demo is null ? ColSettings.Load(AppPaths.Settings) : new ColSettings();
        if (firstLaunch) settings.Save(AppPaths.Settings);
        Win32.AllowDarkMenus();
        ThemeManager.Apply();

        _hub = new Hub(Dispatcher, settings, options.Demo);
        _hub.OpenSettingsRequested += OpenSettings;
        _hub.Quit += Quit;
        _island = new IslandWindow(_hub);
        _island.MenuRequested += () => _tray?.ShowMenu();
        _island.Show();
        _hub.Start();
        Log.Write($"Col {AppPaths.Version} started" + (options.Demo is { } shown ? $", demo {shown.Id()}" : ""));

        if (options.Demo is { } demo)
        {
            DemoScene.Play(demo, _hub, _island, options.Page);
            return;
        }
        StartServices();
        if (options.Link is { } link) _hub.Open(link);
        if (options.OpenSettings || (firstLaunch && !options.Background)) OpenSettings(options.Page);
        SettleMemory();
    }

    /// <summary>
    /// Once Col has started, what it used only to start (reading its styles, its first layout) goes back to Windows:
    /// one full collection, ten seconds in, and nothing after that.
    /// </summary>
    private void SettleMemory()
    {
        var later = new DispatcherTimer(DispatcherPriority.ApplicationIdle, Dispatcher) { Interval = TimeSpan.FromSeconds(10) };
        later.Tick += (_, _) =>
        {
            later.Stop();
            System.Runtime.GCSettings.LargeObjectHeapCompactionMode = System.Runtime.GCLargeObjectHeapCompactionMode.CompactOnce;
            GC.Collect(2, GCCollectionMode.Forced, blocking: true, compacting: true);
        };
        later.Start();
    }

    private void StartServices()
    {
        if (_hub is null) return;
        var api = new ControlApi(_hub.Custom, _hub.Agents, AppPaths.Version) { OpenLink = _hub.Open };
        _pipe = new PipeServer(api);
        _pipe.Start();

        _media = new MediaService(Dispatcher);
        _hub.Media = _media;
        _media.Changed += _hub.OnMedia;
        _ = _media.StartAsync();

        _volume = new VolumeWatcher(Dispatcher);
        _volume.Changed += _hub.OnVolume;
        _volume.Start();

        _tray = new TrayIcon("Col");
        _tray.Clicked += () => OpenSettings(null);
        _tray.MenuEntries = () =>
        [
            new MenuEntry(1, L.Get("Menu_Open")),
            new MenuEntry(2, L.Get("Menu_Settings")),
            new MenuEntry(3, L.Get("Tools_KeepAwake"), Checked: KeepAwake.IsOn),
            MenuEntry.Separator,
            new MenuEntry(9, L.Get("Menu_Quit")),
        ];
        _tray.MenuChosen += choice =>
        {
            switch (choice)
            {
                case 1: _island?.OpenForAWhile(); break;
                case 2: OpenSettings(null); break;
                case 3: _hub?.ToggleKeepAwake(); break;
                case 9: Quit(); break;
            }
        };
    }

    public void OpenSettings(string? page)
    {
        if (_hub is null) return;
        if (_settings is null)
        {
            _settings = new SettingsWindow(_hub);
            _settings.Closed += (_, _) => _settings = null;
        }
        _settings.ShowPage(page);
        _settings.Show();
        if (_settings.WindowState == WindowState.Minimized) _settings.WindowState = WindowState.Normal;
        _settings.Activate();
    }

    /// <summary>Hands a link to the Col already running, through its pipe.</summary>
    private static void HandOver(string link)
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", PipeServer.Name, PipeDirection.InOut, PipeOptions.Asynchronous);
            pipe.Connect(1000);
            using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            pipe.Write(HttpWire.FormatRequest("POST", "/v1/open?url=" + Uri.EscapeDataString(link), null));
            pipe.Flush();
            HttpWire.ReadResponseAsync(pipe, cancellation.Token).GetAwaiter().GetResult();
        }
        catch (Exception error)
        {
            Log.Write("hand over: " + error.Message);
        }
    }

    public void Quit()
    {
        if (_quitting) return;
        _quitting = true;
        if (KeepAwake.IsOn) KeepAwake.Set(false);
        _pipe?.Dispose();
        _volume?.Dispose();
        _media?.Dispose();
        _tray?.Dispose();
        _settings?.Close();
        _island?.Close();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        _tray = null;
        if (_single is not null)
        {
            try { _single.ReleaseMutex(); }
            catch (ApplicationException) { }
            _single.Dispose();
        }
        base.OnExit(e);
    }
}
