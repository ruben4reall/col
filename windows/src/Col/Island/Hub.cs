using System.IO;
using System.Media;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Col.Core;
using Col.Localization;
using Col.Services;

namespace Col.Island;

public enum LyricsStatus
{
    Off,
    Looking,
    Found,
    NotFound,
    Instrumental,
    Unavailable,
}

/// <summary>
/// Everything the island shows, in one place: the activities and the rule that picks the one of the closed island,
/// what plays and its lyrics, the agents, the tools. Lives on the interface's thread; the services hand it their news
/// there.
/// </summary>
internal sealed class Hub
{
    private readonly Dispatcher _dispatcher;
    private readonly DispatcherTimer _expiry;
    private readonly DispatcherTimer _tick;
    private readonly DispatcherTimer _lyricLine;
    private LrclibClient? _lyricsClient;
    private CancellationTokenSource? _lyricsLookup;
    private bool _lowBatteryShown;
    private PowerState _power;

    public ColSettings Settings { get; private set; }
    public DemoState? Demo { get; }
    public bool IsDemo => Demo is not null;
    public ActivityBoard Board { get; } = new();
    public AgentCenter Agents { get; } = new();
    public CustomActivities Custom { get; } = new();
    public ClipboardHistory Clipboard { get; } = new();
    public MediaService? Media { get; set; }

    public NowPlaying Track { get; private set; } = NowPlaying.Nothing;
    public ImageSource? Artwork { get; private set; }
    public Lyrics? Lyrics { get; private set; }
    public LyricsStatus LyricsState { get; private set; } = LyricsStatus.Off;
    public int? LyricIndex { get; private set; }
    public Countdown? Timer { get; private set; }
    public bool KeepAwakeOn => KeepAwake.IsOn;
    /// <summary>The page of the open island the user chose last.</summary>
    public string Page { get; set; } = "home";

    /// <summary>The closed island needs drawing again: what it shows changed.</summary>
    public event Action? Changed;
    public event Action? MediaChanged;
    public event Action? LyricsChanged;
    public event Action? AgentsChanged;
    public event Action? ToolsChanged;
    public event Action? SettingsChanged;
    /// <summary>A permission request arrived: the island opens with it.</summary>
    public event Action? Requested;
    public event Action? Quit;
    public event Action<string?>? OpenSettingsRequested;

    public Hub(Dispatcher dispatcher, ColSettings settings, DemoState? demo)
    {
        _dispatcher = dispatcher;
        Settings = settings;
        Demo = demo;
        _expiry = new DispatcherTimer(DispatcherPriority.Normal, dispatcher);
        _expiry.Tick += (_, _) => Prune();
        _tick = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) { Interval = TimeSpan.FromSeconds(1) };
        _tick.Tick += (_, _) => OnTick();
        _lyricLine = new DispatcherTimer(DispatcherPriority.Normal, dispatcher);
        _lyricLine.Tick += (_, _) =>
        {
            _lyricLine.Stop();
            UpdateLyricLine();
        };
        Agents.Changed += () => _dispatcher.BeginInvoke(OnAgentsChanged);
        Agents.RequestArrived += _ => _dispatcher.BeginInvoke(() => Requested?.Invoke());
        Custom.Changed += () => _dispatcher.BeginInvoke(OnCustomChanged);
    }

    public DateTimeOffset Now => DateTimeOffset.Now;

    public void Start()
    {
        _lyricsClient = new LrclibClient(AppPaths.Lyrics, AppPaths.Version);
        _power = PowerState.Read();
        Refresh();
    }

    // Settings.

    public void Apply(ColSettings settings)
    {
        var lyricsWereOn = Settings.Lyrics;
        Settings = settings;
        if (!IsDemo) settings.Save(AppPaths.Settings);
        if (settings.Lyrics && !lyricsWereOn) LookUpLyrics();
        if (!settings.Lyrics)
        {
            _lyricsLookup?.Cancel();
            Lyrics = null;
            LyricsState = LyricsStatus.Off;
            LyricsChanged?.Invoke();
        }
        UpdateMediaActivity();
        SettingsChanged?.Invoke();
        Refresh();
    }

    public void ClearLyricsCache() => _lyricsClient?.ClearCache();

    public void OpenSettings(string? pane = null) => OpenSettingsRequested?.Invoke(pane);

    public void RequestQuit() => Quit?.Invoke();

    // The board.

    /// <summary>What the closed island shows now, with the line being sung in its middle when that is asked for.</summary>
    public Activity? Current()
    {
        var current = Board.Current(Now);
        if (current?.Id == "media" && Settings.LyricLineClosed && LyricIndex is { } index && Lyrics is { IsSynced: true } lyrics &&
            index < lyrics.Lines.Count && !lyrics.Lines[index].IsPause)
        {
            return current with { Compact = current.Compact with { Middle = lyrics.Lines[index].Text } };
        }
        return current;
    }

    public bool HasAlert => Board.HasAlert(Now) || Agents.Pending.Count > 0;

    private void Refresh()
    {
        Board.Prune(Now);
        ScheduleExpiry();
        Changed?.Invoke();
    }

    private void ScheduleExpiry()
    {
        _expiry.Stop();
        if (Board.NextExpiry(Now) is not { } next) return;
        var wait = next - Now;
        _expiry.Interval = wait < TimeSpan.FromMilliseconds(20) ? TimeSpan.FromMilliseconds(20) : wait + TimeSpan.FromMilliseconds(15);
        _expiry.Start();
    }

    private void Prune()
    {
        _expiry.Stop();
        Custom.Prune(Now);
        Refresh();
    }

    // Media and lyrics.

    public void OnMedia(NowPlaying track, byte[]? artwork)
    {
        var changedTrack = track.TrackKey != Track.TrackKey;
        Track = track;
        if (artwork is not null) Artwork = Decode(artwork);
        if (changedTrack) LookUpLyrics();
        UpdateMediaActivity();
        UpdateLyricLine();
        MediaChanged?.Invoke();
        Refresh();
    }

    public void SetDemoTrack(NowPlaying track, ImageSource artwork, Lyrics lyrics)
    {
        Track = track;
        Artwork = artwork;
        Lyrics = lyrics;
        LyricsState = LyricsStatus.Found;
        UpdateMediaActivity();
        UpdateLyricLine();
        MediaChanged?.Invoke();
        LyricsChanged?.Invoke();
        Refresh();
    }

    private void UpdateMediaActivity()
    {
        if (!Settings.NowPlaying || Track.IsEmpty || !Track.IsPlaying)
        {
            Board.Remove("media");
            return;
        }
        Board.Upsert(new Activity("media", ActivityPriority.Ambient,
            new CompactPresentation(CompactItem.Artwork(), CompactItem.Equalizer(Track.IsPlaying)), Now));
    }

    private static ImageSource? Decode(byte[] bytes)
    {
        if (bytes.Length == 0) return null;
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.StreamSource = new MemoryStream(bytes);
            image.DecodePixelWidth = 160;
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch (Exception)
        {
            return null;
        }
    }

    private async void LookUpLyrics()
    {
        _lyricsLookup?.Cancel();
        _lyricLine.Stop();
        Lyrics = null;
        LyricIndex = null;
        if (!Settings.Lyrics || Track.IsEmpty || IsDemo || _lyricsClient is null)
        {
            LyricsState = Settings.Lyrics ? LyricsStatus.NotFound : LyricsStatus.Off;
            LyricsChanged?.Invoke();
            return;
        }
        LyricsState = LyricsStatus.Looking;
        LyricsChanged?.Invoke();
        var lookup = new CancellationTokenSource();
        _lyricsLookup = lookup;
        var query = Track.Query;
        var key = Track.TrackKey;
        LyricsAnswer answer;
        try
        {
            answer = await Task.Run(() => _lyricsClient.LookUpAsync(query, lookup.Token));
        }
        catch (Exception)
        {
            answer = LyricsAnswer.Unavailable;
        }
        if (lookup.IsCancellationRequested || key != Track.TrackKey) return;
        Lyrics = answer.Lyrics;
        LyricsState = answer.Kind switch
        {
            LyricsAnswerKind.Found => LyricsStatus.Found,
            LyricsAnswerKind.Instrumental => LyricsStatus.Instrumental,
            LyricsAnswerKind.Unavailable => LyricsStatus.Unavailable,
            _ => LyricsStatus.NotFound,
        };
        UpdateLyricLine();
        LyricsChanged?.Invoke();
    }

    /// <summary>
    /// Which line is sung now, and a timer for exactly when the next one starts: no ticking between lines. Only while
    /// someone can see the lines, in the open island or in the closed one.
    /// </summary>
    public void UpdateLyricLine()
    {
        _lyricLine.Stop();
        var previous = LyricIndex;
        if (Lyrics is not { IsSynced: true } lyrics || Track.IsEmpty)
        {
            LyricIndex = null;
        }
        else
        {
            var position = Track.PositionAt(Now);
            LyricIndex = lyrics.IndexAt(position);
            if (Track.IsPlaying && LinesWatched && lyrics.Wait(position, Track.Rate) is { } wait)
            {
                _lyricLine.Interval = TimeSpan.FromSeconds(wait);
                _lyricLine.Start();
            }
        }
        if (previous == LyricIndex) return;
        LyricsChanged?.Invoke();
        if (Settings.LyricLineClosed) Changed?.Invoke();
    }

    /// <summary>Set by the island while the lyrics show in the open island.</summary>
    public bool LyricsOnScreen { get; set; }

    private bool LinesWatched => LyricsOnScreen || Settings.LyricLineClosed;

    public void PlayPause()
    {
        Track = Track.WithPlaying(!Track.IsPlaying, Now);
        Media?.PlayPause();
        UpdateMediaActivity();
        UpdateLyricLine();
        MediaChanged?.Invoke();
        Refresh();
    }

    public void Next() => Media?.Next();

    public void Previous() => Media?.Previous();

    public void Seek(double seconds)
    {
        Track = Track.WithPosition(seconds, Now);
        Media?.Seek(seconds);
        UpdateLyricLine();
        MediaChanged?.Invoke();
    }

    // Agents and scripts.

    private void OnAgentsChanged()
    {
        if (Agents.Activity(Rgba.Blue) is { } activity) Board.Upsert(activity);
        else Board.Remove("agents");
        AgentsChanged?.Invoke();
        Refresh();
    }

    private void OnCustomChanged()
    {
        foreach (var stale in Board.All.Where(a => a.Id.StartsWith("api.", StringComparison.Ordinal)).Select(a => a.Id).ToList())
            Board.Remove(stale);
        foreach (var entry in Custom.Entries) Board.Upsert(CustomActivities.ToActivity(entry));
        AgentsChanged?.Invoke();
        Refresh();
    }

    public void Decide(string requestId, Decision decision) => Agents.Decide(requestId, decision);

    /// <summary>A <c>col://</c> link, from a script, a browser or a second copy of Col.</summary>
    public bool Open(string url)
    {
        if (ColLink.Parse(url) is not { } link) return false;
        _dispatcher.BeginInvoke(() =>
        {
            switch (link.Action)
            {
                case "settings":
                    OpenSettings(link.Query.GetValueOrDefault("pane"));
                    break;
                case "push":
                    if (link.ToRequest() is { } request) Custom.Upsert(request, Now);
                    break;
                case "done":
                    if (link.Query.TryGetValue("id", out var done)) Custom.Finish(done, link.Query.GetValueOrDefault("text"), Now);
                    break;
                case "remove":
                    if (link.Query.TryGetValue("id", out var removed)) Custom.Remove(removed);
                    break;
            }
        });
        return link.Action is "settings" or "push" or "done" or "remove";
    }

    // System displays.

    public void OnVolume(double level, bool muted)
    {
        if (!Settings.VolumeDisplay) return;
        var expires = IsDemo && Demo == DemoState.Volume ? (DateTimeOffset?)null : Now.AddSeconds(1.6);
        Board.Upsert(new Activity("volume", ActivityPriority.Transient,
            new CompactPresentation(CompactItem.Symbol(muted || level <= 0.001 ? "speaker.mute" : "speaker"), CompactItem.Level(level, muted)),
            Now, expires));
        Refresh();
    }

    public void OnPower()
    {
        var before = _power;
        var now = PowerState.Read();
        _power = now;
        ShowPower(now, before);
    }

    public void ShowPower(PowerState now, PowerState? before = null)
    {
        if (!Settings.BatteryDisplay || !now.HasBattery) return;
        var level = now.Percent / 100.0;
        var percent = Rgba.White;
        if (before is null || before.Value.PluggedIn != now.PluggedIn)
        {
            var expires = IsDemo ? (DateTimeOffset?)null : Now.AddSeconds(3);
            Board.Upsert(new Activity("battery", ActivityPriority.Transient,
                new CompactPresentation(CompactItem.Battery(level, now.PluggedIn),
                    CompactItem.Label($"{now.Percent}%", now.PluggedIn ? Rgba.Green : percent)), Now, expires));
        }
        // Low: once at 10 %, until the charger comes.
        if (!now.PluggedIn && now.Percent <= 10 && !_lowBatteryShown)
        {
            _lowBatteryShown = true;
            Board.Upsert(new Activity("battery.low", ActivityPriority.Alert,
                new CompactPresentation(CompactItem.Battery(level, false), CompactItem.Label($"{now.Percent}%", Rgba.Red)), Now, Now.AddSeconds(8)));
        }
        if (now.PluggedIn || now.Percent > 15) _lowBatteryShown = false;
        Refresh();
    }

    // Tools.

    public void StartTimer(TimeSpan length)
    {
        Timer = new Countdown(length, Now);
        UpdateTimer();
    }

    public void PauseOrResumeTimer()
    {
        if (Timer is null) return;
        Timer = Timer.IsPaused ? Timer.Resumed(Now) : Timer.Paused(Now);
        UpdateTimer();
    }

    public void CancelTimer()
    {
        Timer = null;
        UpdateTimer();
    }

    private void OnTick()
    {
        if (Timer is { } timer && timer.IsFinished(Now))
        {
            Timer = null;
            Board.Upsert(new Activity("timer.done", ActivityPriority.Alert,
                new CompactPresentation(CompactItem.Symbol("timer", Rgba.Orange), CompactItem.Label(L.Get("Timer_Done"), Rgba.Orange)),
                Now, Now.AddSeconds(8)));
            if (!IsDemo) SystemSounds.Asterisk.Play();
        }
        UpdateTimer();
    }

    private void UpdateTimer()
    {
        if (Timer is { } timer)
        {
            var remaining = timer.Remaining(Now);
            Board.Upsert(new Activity("timer", ActivityPriority.Standard,
                new CompactPresentation(CompactItem.Symbol("timer", Rgba.Orange),
                    CompactItem.Countdown(timer.Ends, timer.Total, Countdown.Format(remaining), Rgba.Orange)), Now));
            // A tick a second, only while a timer runs.
            if (!timer.IsPaused && !_tick.IsEnabled) _tick.Start();
            if (timer.IsPaused) _tick.Stop();
        }
        else
        {
            Board.Remove("timer");
            _tick.Stop();
        }
        ToolsChanged?.Invoke();
        Refresh();
    }

    public void ToggleKeepAwake()
    {
        KeepAwake.Set(!KeepAwake.IsOn);
        if (KeepAwake.IsOn)
            Board.Upsert(new Activity("awake", ActivityPriority.Ambient, new CompactPresentation(CompactItem.Symbol("cup", Rgba.Yellow)), Now));
        else
            Board.Remove("awake");
        ToolsChanged?.Invoke();
        Refresh();
    }

    public void OnClipboard(string text)
    {
        if (!Settings.ClipboardHistory) return;
        Clipboard.Add(text, Now);
        ToolsChanged?.Invoke();
    }

    public void CopyBack(ClipboardHistory.Entry entry)
    {
        try
        {
            System.Windows.Clipboard.SetText(entry.Text);
        }
        catch (Exception error)
        {
            Log.Write("clipboard: " + error.Message);
        }
    }

    public void TogglePin(Guid id)
    {
        Clipboard.TogglePin(id);
        ToolsChanged?.Invoke();
    }

    public void ForgetClipboard()
    {
        Clipboard.Clear();
        ToolsChanged?.Invoke();
    }
}
