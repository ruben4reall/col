using Stopwatch = System.Diagnostics.Stopwatch;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Col.Core;
using Col.Native;
using Col.Services;

namespace Col.Island;

/// <summary>
/// The island: a borderless, transparent window at the top centre of a monitor that never takes the focus and stays out
/// of Alt-Tab. Its transparent pixels let clicks through to the windows below, so only the capsule itself (and a thin
/// strip along the top edge) catches the pointer. The window never moves while the island animates: springs reshape the
/// capsule inside it, frame by frame while they move, and nothing runs once they rest.
/// </summary>
internal partial class IslandWindow : Window
{
    private readonly Hub _hub;
    private IslandLayout _layout;
    private readonly IslandMachine _machine = new();
    private readonly DispatcherTimer _restTimer;
    private readonly DispatcherTimer _hoverTimer;
    private readonly DispatcherTimer _exitTimer;
    private readonly SpringValue _width;
    private readonly SpringValue _height;
    private readonly SpringValue _radius;
    private readonly SpringValue _opacity;
    private readonly SpringValue _openness;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly DropShadowEffect _shadow = new() { BlurRadius = 26, ShadowDepth = 5, Direction = 270, Color = Colors.Black, Opacity = 0 };
    private bool _rendering;
    private IntPtr _hwnd;
    private FullScreenWatcher? _fullScreen;
    private Activity? _shown;
    private bool _compactCleared;
    private bool _onScreen = true;
    private Native.Monitor? _monitor;
    private bool _frozen;
    private uint[] _privateFormats = [];

    public IslandWindow(Hub hub)
    {
        InitializeComponent();
        _hub = hub;
        _layout = new IslandLayout(hub.Settings.Size);
        _machine.OpensOnHover = hub.Settings.OpenOnHover;
        _restTimer = OneShot(IslandMachine.RestDelay, IslandEvent.RestTimerFired);
        _hoverTimer = OneShot(IslandMachine.HoverDwell, IslandEvent.HoverTimerFired);
        _exitTimer = OneShot(IslandMachine.ExitGrace, IslandEvent.ExitTimerFired);

        var start = _layout.Target(IslandState.Collapsed, Wings.None, 0, hub.Settings.VisibleAtRest || hub.IsDemo, false);
        _width = new SpringValue(start.Width);
        _height = new SpringValue(start.Height);
        _radius = new SpringValue(start.CornerRadius);
        _opacity = new SpringValue(start.Opacity);
        _openness = new SpringValue(0);
        SizeLayers();
        Apply(Now);

        Home.Bind(hub);
        Live.Bind(hub);
        Tools.Bind(hub);
        Card.Bind(hub);
        HomeTab.Checked += (_, _) => ShowPage("home");
        LiveTab.Checked += (_, _) => ShowPage("live");
        ToolsTab.Checked += (_, _) => ShowPage("tools");
        SettingsButton.Content = new System.Windows.Controls.TextBlock
        {
            Text = "\uE713", FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 15,
            Foreground = (Brush)FindResource("Island.Secondary"),
        };
        SettingsButton.Click += (_, _) => hub.OpenSettings();

        MouseEnter += (_, _) => Handle(IslandEvent.PointerEntered);
        MouseLeave += (_, _) => Handle(IslandEvent.PointerExited);
        Body.MouseLeftButtonUp += (_, _) => Press();
        WakeStrip.MouseLeftButtonUp += (_, _) => Press();
        Body.MouseRightButtonUp += (_, e) =>
        {
            e.Handled = true;
            MenuRequested?.Invoke();
        };

        hub.Changed += Update;
        hub.Requested += OnRequested;
        hub.AgentsChanged += UpdateCard;
        hub.SettingsChanged += OnSettingsChanged;
    }

    /// <summary>A right-click on the island: the app shows its menu.</summary>
    public event Action? MenuRequested;

    private double Now => _clock.Elapsed.TotalSeconds;

    private DispatcherTimer OneShot(TimeSpan delay, IslandEvent fired)
    {
        var timer = new DispatcherTimer(DispatcherPriority.Normal, Dispatcher) { Interval = delay };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            Handle(fired);
        };
        return timer;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        _hwnd = new WindowInteropHelper(this).Handle;
        // Never takes the focus, never in Alt-Tab or the taskbar.
        Win32.SetExtendedStyle(_hwnd, Win32.WS_EX_NOACTIVATE | Win32.WS_EX_TOOLWINDOW, Win32.WS_EX_APPWINDOW);
        HwndSource.FromHwnd(_hwnd)?.AddHook(WindowProcedure);
        if (!_hub.IsDemo)
        {
            Win32.AddClipboardFormatListener(_hwnd);
            _privateFormats =
            [
                Win32.RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing"),
                Win32.RegisterClipboardFormat("Clipboard Viewer Ignore"),
            ];
            _fullScreen = new FullScreenWatcher(_hwnd);
            _fullScreen.Changed += _ => UpdatePresence();
        }
        Place();
        _fullScreen?.Start(() => _monitor?.Bounds ?? default);
    }

    protected override void OnClosed(EventArgs e)
    {
        if (_hwnd != IntPtr.Zero && !_hub.IsDemo) Win32.RemoveClipboardFormatListener(_hwnd);
        _fullScreen?.Dispose();
        StopRendering();
        base.OnClosed(e);
    }

    private IntPtr WindowProcedure(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        switch (message)
        {
            case Win32.WM_MOUSEACTIVATE:
                // A click acts without bringing the island forward or taking the focus from the app in front.
                handled = true;
                return new IntPtr(Win32.MA_NOACTIVATE);
            case Win32.WM_DISPLAYCHANGE:
            case Win32.WM_DPICHANGED:
                Dispatcher.BeginInvoke(Place, DispatcherPriority.Background);
                break;
            case Win32.WM_SETTINGCHANGE:
                Motion.Refresh();
                Dispatcher.BeginInvoke(Place, DispatcherPriority.Background);
                break;
            case Win32.WM_CLIPBOARDUPDATE:
                Dispatcher.BeginInvoke(ReadClipboard, DispatcherPriority.Background);
                break;
            case Win32.WM_POWERBROADCAST:
                if (wParam.ToInt64() == Win32.PBT_APMPOWERSTATUSCHANGE) Dispatcher.BeginInvoke(_hub.OnPower);
                break;
            default:
                if (_fullScreen is not null && message == _fullScreen.Message) _fullScreen.OnAppBarMessage(wParam);
                break;
        }
        return IntPtr.Zero;
    }

    /// <summary>
    /// Puts the window at the top centre of the chosen monitor, in its pixels. Called again when monitors, their scale
    /// or their layout change.
    /// </summary>
    public void Place()
    {
        if (_hwnd == IntPtr.Zero) return;
        _monitor = Monitors.Chosen(_hub.Settings.Monitor);
        if (_monitor is null) return;
        var bounds = _monitor.Bounds;
        var (x, y, width, height) = IslandLayout.Placement((bounds.Left, bounds.Top, bounds.Right, bounds.Bottom), _monitor.Scale, _layout.Canvas);
        Win32.SetWindowPos(_hwnd, Win32.HWND_TOPMOST, x, y, width, height, Win32.SWP_NOACTIVATE);
        _fullScreen?.Check();
    }

    private void SizeLayers()
    {
        var (openWidth, openHeight) = _layout.Open;
        ExpandedLayer.Width = openWidth;
        ExpandedLayer.Height = openHeight;
        WakeStrip.Width = _layout.WakeStrip.Width;
        WakeStrip.Height = _layout.WakeStrip.Height;
        Width = _layout.Canvas.Width;
        Height = _layout.Canvas.Height;
    }

    private void OnSettingsChanged()
    {
        _layout = new IslandLayout(_hub.Settings.Size);
        _machine.OpensOnHover = _hub.Settings.OpenOnHover;
        SizeLayers();
        Place();
        Update();
    }

    // The rules.

    private void Press()
    {
        if (_machine.State == IslandState.Expanded) return;
        Handle(IslandEvent.Pressed);
    }

    private void Handle(IslandEvent @event)
    {
        if (_frozen) return;
        Run(_machine.Handle(@event));
    }

    private void Run(IReadOnlyList<IslandEffect> effects)
    {
        foreach (var effect in effects)
        {
            switch (effect)
            {
                case IslandEffect.StartRestTimer: _restTimer.Stop(); _restTimer.Start(); break;
                case IslandEffect.CancelRestTimer: _restTimer.Stop(); break;
                case IslandEffect.StartHoverTimer: _hoverTimer.Stop(); _hoverTimer.Start(); break;
                case IslandEffect.CancelHoverTimer: _hoverTimer.Stop(); break;
                case IslandEffect.StartExitTimer: _exitTimer.Stop(); _exitTimer.Start(); break;
                case IslandEffect.CancelExitTimer: _exitTimer.Stop(); break;
            }
        }
        Update();
    }

    /// <summary>Opens the island from the tray's menu. It closes a few seconds later unless the pointer comes to it.</summary>
    public void OpenForAWhile()
    {
        Handle(IslandEvent.Pressed);
        var later = new DispatcherTimer(DispatcherPriority.Normal, Dispatcher) { Interval = TimeSpan.FromSeconds(5) };
        later.Tick += (_, _) =>
        {
            later.Stop();
            Handle(IslandEvent.ExitTimerFired);
        };
        later.Start();
    }

    /// <summary>Puts the island in a state for a demo, and keeps it there whatever the pointer does.</summary>
    public void Freeze(IslandState state, string page = "home")
    {
        _frozen = true;
        switch (state)
        {
            case IslandState.Peek:
                _machine.Handle(IslandEvent.PointerEntered);
                _machine.Handle(IslandEvent.RestTimerFired);
                break;
            case IslandState.Expanded:
                _machine.Handle(IslandEvent.Pressed);
                break;
        }
        (page switch { "live" => LiveTab, "tools" => ToolsTab, _ => HomeTab }).IsChecked = true;
        ShowPage(page);
        Update();
    }

    private void OnRequested()
    {
        UpdateCard();
        if (_frozen)
        {
            _machine.Handle(IslandEvent.Requested);
            Update();
            return;
        }
        Run(_machine.Handle(IslandEvent.Requested));
    }

    private void UpdateCard()
    {
        var waiting = Card.Refresh();
        Card.Visibility = waiting ? Visibility.Visible : Visibility.Collapsed;
        PagesView.Visibility = waiting ? Visibility.Collapsed : Visibility.Visible;
        var effects = _machine.Hold(waiting);
        if (!_frozen) Run(effects);
        UpdateHomeOnScreen();
        UpdatePresence();
    }

    private void ShowPage(string page)
    {
        _hub.Page = page;
        Home.Visibility = page == "home" ? Visibility.Visible : Visibility.Collapsed;
        Live.Visibility = page == "live" ? Visibility.Visible : Visibility.Collapsed;
        Tools.Visibility = page == "tools" ? Visibility.Visible : Visibility.Collapsed;
        if (page == "live") Live.Refresh();
        if (page == "tools") Tools.Refresh();
        UpdateHomeOnScreen();
    }

    private void UpdateHomeOnScreen() =>
        Home.SetOnScreen(_machine.State == IslandState.Expanded && _hub.Page == "home" && Card.Visibility != Visibility.Visible);

    // What the island shows.

    private static double WingOf(CompactItem? item) => item is null ? 0 : CompactViews.Width(item) + 2 * CompactViews.WingPadding;

    private void Update()
    {
        var activity = _hub.Current();
        var compact = activity?.Compact;
        var state = _machine.State;
        if (state != IslandState.Expanded && (!Equals(activity, _shown) || _compactCleared)) ShowCompact(activity);
        var wings = compact is null ? Wings.None : new Wings(WingOf(compact.Leading), WingOf(compact.Trailing));
        var middle = compact?.Middle is { Length: > 0 } line ? CompactViews.MeasureText(line, 12.5) + 30 : 0;
        var target = _layout.Target(state, wings, middle, _hub.Settings.VisibleAtRest || _hub.IsDemo, compact is not null);
        AnimateTo(target, state);
        UpdateHomeOnScreen();
        UpdatePresence();
    }

    /// <summary>Builds the closed island's items for an activity.</summary>
    private void ShowCompact(Activity? activity)
    {
        _shown = activity;
        _compactCleared = false;
        var compact = activity?.Compact;
        var scale = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        LeadingSlot.Content = compact?.Leading is { } leading ? CompactViews.Make(leading, _hub.Artwork, scale) : null;
        TrailingSlot.Content = compact?.Trailing is { } trailing ? CompactViews.Make(trailing, _hub.Artwork, scale) : null;
        LeadingSlot.Margin = new Thickness(CompactViews.WingPadding + 2, 0, 0, 0);
        TrailingSlot.Margin = new Thickness(0, 0, CompactViews.WingPadding + 2, 0);
        MiddleText.Text = compact?.Middle ?? "";
        MiddleText.MaxWidth = IslandLayout.MaximumMiddle - 24;
    }

    private void AnimateTo(IslandShape target, IslandState state)
    {
        var now = Now;
        var spring = Spring.Toward(state, !Motion.Enabled);
        _width.Animate(target.Width, spring, now);
        _height.Animate(target.Height, spring, now);
        _radius.Animate(target.CornerRadius, spring, now);
        _opacity.Animate(target.Opacity, Motion.Enabled ? new Spring(0.3, 0) : Spring.Reduced, now);
        var open = state == IslandState.Expanded;
        _openness.Animate(open ? 1 : 0, open ? new Spring(0.45, 0) : new Spring(0.24, 0), now);
        ExpandedLayer.IsHitTestVisible = open;
        if (open) ExpandedLayer.Visibility = Visibility.Visible;
        StartRendering();
    }

    private void StartRendering()
    {
        if (_rendering) return;
        _rendering = true;
        CompositionTarget.Rendering += OnRendering;
    }

    private void StopRendering()
    {
        if (!_rendering) return;
        _rendering = false;
        CompositionTarget.Rendering -= OnRendering;
    }

    private void OnRendering(object? sender, EventArgs e)
    {
        var now = Now;
        var moving = _width.Step(now) | _height.Step(now) | _radius.Step(now) | _opacity.Step(now) | _openness.Step(now);
        Apply(now);
        // At rest, nothing runs.
        if (!moving) StopRendering();
    }

    private void Apply(double now)
    {
        var width = Math.Max(2, _width.ValueAt(now));
        var height = Math.Max(2, _height.ValueAt(now));
        var radius = Math.Clamp(_radius.ValueAt(now), 0, Math.Min(width, height) / 2);
        var opacity = Math.Clamp(_opacity.ValueAt(now), 0, 1);
        var open = Math.Clamp(_openness.ValueAt(now), 0, 1);

        Body.Width = width;
        Body.Height = height;
        Body.CornerRadius = new CornerRadius(radius);
        Body.Opacity = opacity;

        CompactLayer.Width = width;
        CompactLayer.Height = height;
        CompactLayer.Opacity = opacity * Math.Clamp(1 - open * 2.2, 0, 1);
        // Hidden behind the open island, the closed island's items stop: no equalizer dances unseen.
        if (open > 0.6 && !_compactCleared && _machine.State == IslandState.Expanded)
        {
            LeadingSlot.Content = null;
            TrailingSlot.Content = null;
            _compactCleared = true;
        }

        var (openWidth, _) = _layout.Open;
        ExpandedLayer.Opacity = Math.Clamp((open - 0.3) / 0.7, 0, 1);
        ExpandedLayer.Clip = new RectangleGeometry(new Rect((openWidth - width) / 2, 0, width, height), radius, radius);
        if (open <= 0.001 && _machine.State != IslandState.Expanded) ExpandedLayer.Visibility = Visibility.Collapsed;

        Bridge.Width = Math.Max(width, 40);
        Bridge.Visibility = opacity > 0.02 ? Visibility.Visible : Visibility.Collapsed;

        // A soft shadow under the open island only: at rest the capsule has none, and clicks around it pass through.
        if (open > 0.01)
        {
            if (Body.Effect is null) Body.Effect = _shadow;
            _shadow.Opacity = 0.5 * open;
        }
        else if (Body.Effect is not null)
        {
            Body.Effect = null;
        }
    }

    /// <summary>Steps aside under a full-screen app, unless something needs the user.</summary>
    private void UpdatePresence()
    {
        var shown = IslandPresence.IsShown(_fullScreen?.IsFullScreen ?? false, _hub.HasAlert);
        if (shown == _onScreen) return;
        _onScreen = shown;
        if (shown) Show();
        else Hide();
    }

    // The clipboard.

    private void ReadClipboard()
    {
        if (_hub.IsDemo || !_hub.Settings.ClipboardHistory) return;
        try
        {
            // Copies that password managers mark as private are never kept.
            if (_privateFormats.Any(format => format != 0 && Win32.IsClipboardFormatAvailable(format))) return;
            if (System.Windows.Clipboard.GetData("CanIncludeInClipboardHistory") is System.IO.MemoryStream flag &&
                flag.Length >= 4 && BitConverter.ToInt32(flag.ToArray(), 0) == 0) return;
            if (!System.Windows.Clipboard.ContainsText()) return;
            _hub.OnClipboard(System.Windows.Clipboard.GetText());
        }
        catch (Exception error) when (error is System.Runtime.InteropServices.COMException or System.Runtime.InteropServices.ExternalException)
        {
            // Another app holds the clipboard: this copy is missed.
        }
    }
}
