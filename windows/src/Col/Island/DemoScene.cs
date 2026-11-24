using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Col.Core;
using Col.Services;

namespace Col.Island;

/// <summary>
/// Puts the island in a state with made-up data, so screenshots come out the same every time:
/// <c>Col.exe --demo lyrics</c>. Nothing of the user's is read or shown.
/// </summary>
internal static class DemoScene
{
    public static void Play(DemoState demo, Hub hub, IslandWindow island, string? page)
    {
        switch (demo)
        {
            case DemoState.Collapsed:
                island.Freeze(IslandState.Collapsed);
                break;
            case DemoState.Peek:
                island.Freeze(IslandState.Peek);
                break;
            case DemoState.Music:
                PlaySong(hub);
                island.Freeze(IslandState.Collapsed);
                break;
            case DemoState.Lyrics:
                PlaySong(hub);
                island.Freeze(IslandState.Expanded, "home");
                break;
            case DemoState.AgentPermission:
                island.Freeze(IslandState.Collapsed);
                if (CodingAgent.Claude.EventFrom(Core.Demo.PermissionRequest()) is { } request) _ = hub.Agents.Receive(request);
                break;
            case DemoState.Agents:
                foreach (var @event in Core.Demo.WorkingAgents()) _ = hub.Agents.Receive(@event);
                island.Freeze(IslandState.Collapsed);
                break;
            case DemoState.Live:
                foreach (var @event in Core.Demo.WorkingAgents()) _ = hub.Agents.Receive(@event);
                hub.Custom.Upsert(new ActivityRequest("build") { Title = "Build", Subtitle = "12 of 40 files", Symbol = "hammer.fill", Tint = "orange", Progress = 0.4 }, hub.Now);
                island.Freeze(IslandState.Expanded, "live");
                break;
            case DemoState.Volume:
                hub.OnVolume(0.62, false);
                island.Freeze(IslandState.Collapsed);
                break;
            case DemoState.Battery:
                hub.ShowPower(new PowerState(true, 82, true, true));
                island.Freeze(IslandState.Collapsed);
                break;
            case DemoState.Timer:
                hub.StartTimer(TimeSpan.FromMinutes(4) + TimeSpan.FromSeconds(8));
                island.Freeze(IslandState.Collapsed);
                break;
            case DemoState.Tools:
                foreach (var copy in Core.Demo.Copies.Reverse()) hub.OnClipboard(copy);
                if (hub.Clipboard.Ordered.LastOrDefault() is { } first) hub.TogglePin(first.Id);
                hub.StartTimer(TimeSpan.FromMinutes(25));
                island.Freeze(IslandState.Expanded, "tools");
                break;
            case DemoState.Settings:
                island.Freeze(IslandState.Collapsed);
                hub.OpenSettings(page);
                break;
            case DemoState.Intro:
                island.PlayIntro(sound: false);
                break;
            case DemoState.Showcase:
                // The film the README shows: a few seconds apart, the steps a person would see.
                After(3.0, () => island.PlayIntro(sound: false));
                After(6.5, () => PlaySong(hub));
                After(9.0, island.OpenForAWhile);
                break;
        }
    }

    private static void After(double seconds, Action action)
    {
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            action();
        };
        timer.Start();
    }

    private static void PlaySong(Hub hub)
    {
        var lyrics = Lyrics.Parse(Core.Demo.TrackLyrics);
        if (lyrics is null) return;
        hub.SetDemoTrack(Core.Demo.Track(hub.Now), Cover(), lyrics);
    }

    /// <summary>A cover drawn for the demo: a pass between two peaks at night, in Col's blues.</summary>
    public static ImageSource Cover()
    {
        const int size = 160;
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            var sky = new LinearGradientBrush(Color.FromRgb(0x0A, 0x1F, 0x44), Color.FromRgb(0x0A, 0x84, 0xFF), 90);
            context.DrawRectangle(sky, null, new Rect(0, 0, size, size));
            context.DrawEllipse(new SolidColorBrush(Color.FromRgb(0xB8, 0xDA, 0xFF)), null, new Point(112, 46), 14, 14);
            var far = Geometry.Parse("M0,118 L42,64 L70,96 L96,58 L160,120 L160,160 L0,160 Z");
            context.DrawGeometry(new SolidColorBrush(Color.FromRgb(0x0F, 0x2E, 0x5C)), null, far);
            var near = Geometry.Parse("M0,138 L30,106 L62,128 L80,112 L104,130 L134,100 L160,126 L160,160 L0,160 Z");
            context.DrawGeometry(new SolidColorBrush(Color.FromRgb(0x05, 0x08, 0x0A)), null, near);
        }
        var bitmap = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }
}
