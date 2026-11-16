using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Col.Core;
using Col.Localization;

namespace Col.Island;

/// <summary>
/// Home: the player beside the song's words, the line being sung lit, as Apple Music shows them. A line is a button:
/// a click goes there in the song. While nothing plays, the time.
/// </summary>
internal partial class HomePage : UserControl
{
    private Hub? _hub;
    private readonly DispatcherTimer _second;
    private readonly List<Button> _lineViews = [];
    private Lyrics? _shownLyrics;
    private int? _shownIndex;
    private bool _onScreen;

    public HomePage()
    {
        InitializeComponent();
        _second = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _second.Tick += (_, _) => UpdateClock();
        PreviousButton.Content = Glyphs.Make("previous", Brushes.White, 16);
        NextButton.Content = Glyphs.Make("next", Brushes.White, 16);
        PreviousButton.Click += (_, _) => _hub?.Previous();
        NextButton.Click += (_, _) => _hub?.Next();
        PlayButton.Click += (_, _) => _hub?.PlayPause();
        Scrubber.MouseLeftButtonUp += OnScrub;
        LyricsArea.SizeChanged += (_, _) => ScrollToLine(animated: false);
        IdleGlyph.Content = Glyphs.Make("music", (Brush)FindResource("Island.Tertiary"), 22);
    }

    public void Bind(Hub hub)
    {
        _hub = hub;
        hub.MediaChanged += Refresh;
        hub.LyricsChanged += RefreshLyrics;
        Refresh();
        RefreshLyrics();
    }

    /// <summary>The page shows or hides with the open island: the clock and the line timer run only while it shows.</summary>
    public void SetOnScreen(bool onScreen)
    {
        if (onScreen == _onScreen) return;
        _onScreen = onScreen;
        if (_hub is not null)
        {
            _hub.LyricsOnScreen = onScreen;
            _hub.UpdateLyricLine();
        }
        if (onScreen)
        {
            UpdateClock();
            _second.Start();
            ScrollToLine(animated: false);
        }
        else
        {
            _second.Stop();
        }
    }

    private void Refresh()
    {
        if (_hub is null) return;
        var track = _hub.Track;
        var nothing = track.IsEmpty || !_hub.Settings.NowPlaying;
        Idle.Visibility = nothing ? Visibility.Visible : Visibility.Collapsed;
        Playing.Visibility = nothing ? Visibility.Collapsed : Visibility.Visible;
        Title.Text = track.Title;
        Artist.Text = track.Artist;
        ArtworkSlot.Content = CompactViews.Artwork(_hub.Artwork, 54, 10);
        PlayButton.Content = Glyphs.Make(track.IsPlaying ? "pause" : "play", Brushes.White, 22);
        UpdateClock();
    }

    /// <summary>Once a second while the page shows: the scrubber, or the time when nothing plays.</summary>
    private void UpdateClock()
    {
        if (_hub is null) return;
        var now = DateTime.Now;
        Clock.Text = now.ToString("t", CultureInfo.CurrentCulture);
        Date.Text = now.ToString("D", CultureInfo.CurrentCulture);
        var track = _hub.Track;
        var position = track.PositionAt(DateTimeOffset.Now);
        Elapsed.Text = NowPlaying.Clock(position);
        Remaining.Text = track.Duration > 0 ? "-" + NowPlaying.Clock(track.Duration - position) : "";
        var width = ScrubTrack.ActualWidth > 0 ? ScrubTrack.ActualWidth : PlayerColumn.Width.Value;
        ScrubFill.Width = track.Duration > 0 ? Math.Max(4, width * Math.Clamp(position / track.Duration, 0, 1)) : 0;
    }

    private void OnScrub(object sender, MouseButtonEventArgs e)
    {
        if (_hub is null || _hub.Track.Duration <= 0 || ScrubTrack.ActualWidth <= 0) return;
        var fraction = Math.Clamp(e.GetPosition(ScrubTrack).X / ScrubTrack.ActualWidth, 0, 1);
        _hub.Seek(fraction * _hub.Track.Duration);
        UpdateClock();
    }

    private void RefreshLyrics()
    {
        if (_hub is null) return;
        var lyrics = _hub.Lyrics;
        if (!ReferenceEquals(lyrics, _shownLyrics)) BuildLines(lyrics);
        var (glyph, note) = _hub.LyricsState switch
        {
            LyricsStatus.Off => ("music", L.Get("Lyrics_Off")),
            LyricsStatus.Looking => ("music", L.Get("Lyrics_Looking")),
            LyricsStatus.Instrumental => ("music", L.Get("Lyrics_Instrumental")),
            LyricsStatus.Unavailable => ("music", L.Get("Lyrics_Unavailable")),
            LyricsStatus.NotFound => ("music", L.Get("Lyrics_NotFound")),
            _ => (null, ""),
        };
        var showNote = lyrics is null;
        LyricsNote.Visibility = showNote ? Visibility.Visible : Visibility.Collapsed;
        Lines.Visibility = showNote ? Visibility.Collapsed : Visibility.Visible;
        NoteText.Text = note;
        NoteGlyph.Content = glyph is null ? null : Glyphs.Make(glyph, (Brush)FindResource("Island.Tertiary"), 18);
        HighlightLine(_hub.LyricIndex);
    }

    private void BuildLines(Lyrics? lyrics)
    {
        _shownLyrics = lyrics;
        _shownIndex = null;
        Lines.Children.Clear();
        _lineViews.Clear();
        LinesShift.BeginAnimation(TranslateTransform.YProperty, null);
        LinesShift.Y = 0;
        if (lyrics is null) return;
        foreach (var line in lyrics.Lines)
        {
            var text = new TextBlock
            {
                Text = line.IsPause ? "•  •  •" : line.Text,
                TextWrapping = TextWrapping.Wrap,
                FontSize = 14,
                FontWeight = FontWeights.SemiBold,
                Foreground = (Brush)FindResource("Island.Tertiary"),
            };
            var button = new Button
            {
                Style = (Style)FindResource("Island.Row"),
                Content = text,
                Padding = new Thickness(6, 3, 6, 3),
                Margin = new Thickness(-6, 0, 0, 1),
                Tag = line.Time,
                IsEnabled = lyrics.IsSynced,
            };
            button.Click += (_, _) => _hub?.Seek(line.Time + 0.01);
            Lines.Children.Add(button);
            _lineViews.Add(button);
        }
    }

    private void HighlightLine(int? index)
    {
        if (_shownIndex == index) return;
        if (_shownIndex is { } old && old < _lineViews.Count) Paint(_lineViews[old], current: false);
        _shownIndex = index;
        if (index is { } now && now < _lineViews.Count) Paint(_lineViews[now], current: true);
        ScrollToLine(animated: _onScreen);
    }

    private void Paint(Button line, bool current)
    {
        if (line.Content is TextBlock text)
            text.Foreground = current ? Brushes.White : (Brush)FindResource("Island.Tertiary");
    }

    /// <summary>Brings the line being sung to a third of the way down, in a short ease, the way the lines roll in Apple
    /// Music; without animations, at once.</summary>
    private void ScrollToLine(bool animated)
    {
        if (_lineViews.Count == 0 || LyricsArea.ActualHeight <= 0) return;
        var index = _shownIndex ?? 0;
        if (index >= _lineViews.Count) return;
        Lines.UpdateLayout();
        var top = _lineViews[index].TranslatePoint(new Point(0, 0), Lines).Y;
        var target = Math.Min(0, LyricsArea.ActualHeight * 0.3 - top);
        if (!animated || !Services.Motion.Enabled)
        {
            LinesShift.BeginAnimation(TranslateTransform.YProperty, null);
            LinesShift.Y = target;
            return;
        }
        var roll = new DoubleAnimation(target, TimeSpan.FromMilliseconds(420))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        };
        LinesShift.BeginAnimation(TranslateTransform.YProperty, roll);
    }
}
