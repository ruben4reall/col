using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Col.Core;
using Col.Localization;

namespace Col.Island;

/// <summary>Live: every agent session and every activity scripts pushed, the ones that need the user first.</summary>
internal partial class LivePage : UserControl
{
    private Hub? _hub;

    public LivePage()
    {
        InitializeComponent();
        EmptyGlyph.Content = Glyphs.Make("terminal", (Brush)FindResource("Island.Tertiary"), 22);
    }

    public void Bind(Hub hub)
    {
        _hub = hub;
        hub.AgentsChanged += Refresh;
        Refresh();
    }

    public void Refresh()
    {
        if (_hub is null) return;
        Rows.Children.Clear();
        foreach (var session in _hub.Agents.Sessions) Rows.Children.Add(SessionRow(session));
        foreach (var entry in _hub.Custom.Entries) Rows.Children.Add(ActivityRow(entry));
        Empty.Visibility = Rows.Children.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private static Brush Secondary => (Brush)Application.Current.FindResource("Island.Secondary");

    private static FrameworkElement Row(FrameworkElement leading, string title, string? caption, string detail, Brush detailBrush, FrameworkElement? trailing = null)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 8, 10) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        leading.Margin = new Thickness(0, 1, 11, 0);
        leading.VerticalAlignment = VerticalAlignment.Top;
        grid.Children.Add(leading);
        var texts = new StackPanel();
        var head = new TextBlock { FontSize = 13, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis };
        head.Inlines.Add(new System.Windows.Documents.Run(title));
        if (!string.IsNullOrEmpty(caption))
            head.Inlines.Add(new System.Windows.Documents.Run("  " + caption) { Foreground = Secondary, FontWeight = FontWeights.Normal, FontSize = 12 });
        texts.Children.Add(head);
        texts.Children.Add(new TextBlock
        {
            Text = detail, FontSize = 12, Foreground = detailBrush, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 1, 0, 0),
        });
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);
        if (trailing is not null)
        {
            trailing.VerticalAlignment = VerticalAlignment.Center;
            trailing.Margin = new Thickness(10, 0, 0, 0);
            Grid.SetColumn(trailing, 2);
            grid.Children.Add(trailing);
        }
        return grid;
    }

    private static FrameworkElement SessionRow(AgentSession session)
    {
        var (detail, brush, trailing) = session.State.Kind switch
        {
            AgentStateKind.Waiting => (session.State.Detail ?? L.Get("Agent_Waiting"), Glyphs.Brush(Rgba.Orange), Glyphs.Make("hand", Glyphs.Brush(Rgba.Orange), 16)),
            AgentStateKind.Working => (session.State.Detail ?? L.Get("Agent_Working"), Secondary, CompactViews.Make(CompactItem.Spinner(Rgba.Blue), null, 1)),
            AgentStateKind.Done => (L.Get("Agent_Done"), Glyphs.Brush(Rgba.Green), Glyphs.Make("check", Glyphs.Brush(Rgba.Green), 16, CompactViews.Island)),
            _ => (L.Get("Agent_Idle"), Secondary, (FrameworkElement?)null),
        };
        var name = session.Agent ?? "";
        return Row(CompactViews.AgentLogo(session.Agent ?? session.Project, 22), session.Project, name == session.Project ? null : name, detail, brush, trailing);
    }

    private static FrameworkElement ActivityRow(CustomActivities.Entry entry)
    {
        var request = entry.Request;
        var tint = Glyphs.Brush(request.ResolvedTint);
        var leading = new Grid { Width = 22, Height = 22 };
        leading.Children.Add(new Border { CornerRadius = new CornerRadius(6), Background = Glyphs.Brush(255, 255, 255, 0x1A) });
        var symbol = ActivityRequest.SymbolItem(request.Symbol, request.ResolvedTint);
        var glyph = CompactViews.Make(symbol, null, 1);
        glyph.HorizontalAlignment = HorizontalAlignment.Center;
        leading.Children.Add(glyph);
        FrameworkElement? trailing = entry.Finished
            ? Glyphs.Make("check", Glyphs.Brush(Rgba.Green), 16, CompactViews.Island)
            : request.Progress is { } progress ? CompactViews.Ring(progress, tint, 18) : null;
        var detail = entry.Finished
            ? request.Text ?? L.Get("Agent_Done")
            : request.Subtitle ?? (request.Progress is { } p ? $"{Math.Round(p * 100)}%" : request.Text ?? "");
        return Row(leading, request.Title ?? request.Id, null, detail, entry.Finished ? Glyphs.Brush(Rgba.Green) : Secondary, trailing);
    }
}
