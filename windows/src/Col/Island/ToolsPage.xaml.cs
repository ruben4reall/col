using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Col.Core;
using Col.Localization;

namespace Col.Island;

/// <summary>Tools: a timer that counts down in the closed island, keep awake, and the clipboard's last copies.</summary>
internal partial class ToolsPage : UserControl
{
    private Hub? _hub;
    private TimeSpan _chosen = TimeSpan.FromMinutes(5);
    private string _copiesShown = "";

    public ToolsPage()
    {
        InitializeComponent();
        CancelTimer.Content = Glyphs.Make("close", (Brush)FindResource("Island.Secondary"), 12);
        CancelTimer.Click += (_, _) => _hub?.CancelTimer();
        StartTimer.Click += (_, _) =>
        {
            if (_hub is null) return;
            if (_hub.Timer is null) _hub.StartTimer(_chosen);
            else _hub.PauseOrResumeTimer();
        };
        KeepAwakeButton.Click += (_, _) => _hub?.ToggleKeepAwake();
        ClearClipboard.Click += (_, _) => _hub?.ForgetClipboard();
        foreach (var minutes in new[] { 1, 5, 10, 25 })
        {
            var preset = new Button
            {
                Style = (Style)FindResource("Island.Pill"),
                Content = minutes.ToString(CultureInfo.CurrentCulture),
                Height = 26,
                Padding = new Thickness(0),
                Width = minutes >= 10 ? 38 : 32,
                FontSize = 12,
                Margin = new Thickness(0, 0, 6, 0),
                ToolTip = L.Format("Tools_Minutes", minutes),
            };
            preset.Click += (_, _) =>
            {
                _chosen = TimeSpan.FromMinutes(minutes);
                _hub?.StartTimer(_chosen);
            };
            Presets.Children.Add(preset);
        }
    }

    public void Bind(Hub hub)
    {
        _hub = hub;
        hub.ToolsChanged += Refresh;
        Refresh();
    }

    public void Refresh()
    {
        if (_hub is null) return;
        var timer = _hub.Timer;
        var blue = Glyphs.Brush(Rgba.Blue);
        TimerText.Text = Countdown.Format(timer?.Remaining(_hub.Now) ?? _chosen);
        TimerText.Foreground = timer is null ? Brushes.White : Glyphs.Brush(Rgba.Orange);
        StartTimer.Content = Glyphs.Make(timer is { IsPaused: false } ? "pause" : "play", blue, 13);
        StartTimer.ToolTip = L.Get(timer is { IsPaused: false } ? "Tools_Pause" : "Tools_Start");
        CancelTimer.Visibility = timer is null ? Visibility.Collapsed : Visibility.Visible;

        var awake = _hub.KeepAwakeOn;
        CupSlot.Content = Glyphs.Make("cup", awake ? Glyphs.Brush(Rgba.Yellow) : (Brush)FindResource("Island.Secondary"), 16);
        AwakeState.Text = L.Get(awake ? "State_On" : "State_Off");
        AwakeState.Foreground = awake ? Glyphs.Brush(Rgba.Yellow) : (Brush)FindResource("Island.Tertiary");

        // The rows are made again only when the copies changed, not at each second of a timer.
        var copies = _hub.Clipboard.Ordered.Take(24).ToList();
        var signature = string.Join("|", copies.Select(c => $"{c.Id}{c.Pinned}"));
        if (signature != _copiesShown)
        {
            _copiesShown = signature;
            Copies.Children.Clear();
            foreach (var entry in copies) Copies.Children.Add(CopyRow(entry));
        }
        NoCopies.Visibility = Copies.Children.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        NoCopies.Text = L.Get(_hub.Settings.ClipboardHistory ? "Tools_Clipboard_Empty" : "Tools_Clipboard_Off");
    }

    private FrameworkElement CopyRow(ClipboardHistory.Entry entry)
    {
        var pin = new Button
        {
            Style = (Style)FindResource("Island.IconButton"),
            Width = 24,
            Height = 24,
            Content = Glyphs.Make(entry.Pinned ? "pinned" : "pin", entry.Pinned ? Glyphs.Brush(Rgba.Orange) : (Brush)FindResource("Island.Tertiary"), 13),
            ToolTip = L.Get(entry.Pinned ? "Tools_Unpin" : "Tools_Pin"),
        };
        pin.Click += (_, e) =>
        {
            e.Handled = true;
            _hub?.TogglePin(entry.Id);
        };
        DockPanel.SetDock(pin, Dock.Right);
        var text = new TextBlock
        {
            Text = ClipboardHistory.Preview(entry.Text), FontSize = 12.5, TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var row = new DockPanel { LastChildFill = true };
        row.Children.Add(pin);
        row.Children.Add(text);
        var button = new Button
        {
            Style = (Style)FindResource("Island.Row"), Content = row, Padding = new Thickness(8, 1, 2, 1), Margin = new Thickness(-8, 0, 4, 0),
            ToolTip = L.Get("Tools_CopyAgain"),
        };
        button.Click += (_, _) => _hub?.CopyBack(entry);
        return button;
    }
}
