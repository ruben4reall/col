using System.IO;
using System.Windows.Threading;
using Col.Core;
using Windows.Media.Control;

namespace Col.Services;

/// <summary>
/// What plays, from Windows' own media controls (the ones the volume flyout shows): Spotify, a browser, the Media
/// Player, any app that publishes them. Event-driven: nothing is asked while nothing changes.
/// </summary>
internal sealed class MediaService : IDisposable
{
    private readonly Dispatcher _dispatcher;
    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private GlobalSystemMediaTransportControlsSession? _session;
    private string _artworkKey = "";
    private bool _refreshing;
    private bool _again;

    /// <summary>The track, and the artwork's bytes when it changed (null when unchanged, empty when gone).</summary>
    public event Action<NowPlaying, byte[]?>? Changed;

    public NowPlaying Current { get; private set; } = NowPlaying.Nothing;

    public MediaService(Dispatcher dispatcher) => _dispatcher = dispatcher;

    public async Task StartAsync()
    {
        try
        {
            _manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            _manager.CurrentSessionChanged += (_, _) => _dispatcher.BeginInvoke(() => Attach(_manager?.GetCurrentSession()));
            Attach(_manager.GetCurrentSession());
        }
        catch (Exception error)
        {
            Log.Write("media: " + error.Message);
        }
    }

    private void Attach(GlobalSystemMediaTransportControlsSession? session)
    {
        if (_session is not null)
        {
            _session.MediaPropertiesChanged -= OnChanged;
            _session.PlaybackInfoChanged -= OnChanged;
            _session.TimelinePropertiesChanged -= OnChanged;
        }
        _session = session;
        if (_session is not null)
        {
            _session.MediaPropertiesChanged += OnChanged;
            _session.PlaybackInfoChanged += OnChanged;
            _session.TimelinePropertiesChanged += OnChanged;
        }
        Refresh();
    }

    private void OnChanged<T>(GlobalSystemMediaTransportControlsSession sender, T args) => _dispatcher.BeginInvoke(Refresh);

    private async void Refresh()
    {
        // Players send several events at once: one read for all of them, and one more for any that came during it.
        if (_refreshing)
        {
            _again = true;
            return;
        }
        _refreshing = true;
        try
        {
            await Task.Delay(40);
            var session = _session;
            if (session is null)
            {
                Publish(NowPlaying.Nothing, _artworkKey.Length > 0 ? [] : null);
                _artworkKey = "";
                return;
            }
            var properties = await session.TryGetMediaPropertiesAsync();
            var playback = session.GetPlaybackInfo();
            var timeline = session.GetTimelineProperties();
            var duration = (timeline.EndTime - timeline.StartTime).TotalSeconds;
            var now = DateTimeOffset.Now;
            var reported = timeline.LastUpdatedTime;
            if (reported == default || reported > now) reported = now;
            var track = new NowPlaying
            {
                IsPlaying = playback.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing,
                Title = properties?.Title ?? "",
                Artist = properties?.Artist is { Length: > 0 } artist ? artist : properties?.AlbumArtist ?? "",
                Album = properties?.AlbumTitle ?? "",
                Duration = duration > 0 ? duration : 0,
                Elapsed = Math.Max(0, (timeline.Position - timeline.StartTime).TotalSeconds),
                Reported = reported,
                Rate = playback.PlaybackRate ?? 1,
                Source = session.SourceAppUserModelId ?? "",
            };
            byte[]? artwork = null;
            if (track.TrackKey != _artworkKey)
            {
                artwork = await ReadArtwork(properties) ?? [];
                _artworkKey = track.TrackKey;
            }
            Publish(track, artwork);
        }
        catch (Exception error)
        {
            Log.Write("media: " + error.Message);
        }
        finally
        {
            _refreshing = false;
            if (_again)
            {
                _again = false;
                _ = _dispatcher.BeginInvoke(Refresh);
            }
        }
    }

    private void Publish(NowPlaying track, byte[]? artwork)
    {
        Current = track;
        Changed?.Invoke(track, artwork);
    }

    private static async Task<byte[]?> ReadArtwork(GlobalSystemMediaTransportControlsSessionMediaProperties? properties)
    {
        if (properties?.Thumbnail is null) return null;
        try
        {
            using var stream = await properties.Thumbnail.OpenReadAsync();
            using var input = stream.AsStreamForRead();
            using var buffer = new MemoryStream();
            await input.CopyToAsync(buffer);
            // A cover is a few hundred kilobytes at most; anything bigger is not one.
            return buffer.Length is > 0 and < 8 * 1024 * 1024 ? buffer.ToArray() : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public async void PlayPause()
    {
        if (_session is null) return;
        try { await _session.TryTogglePlayPauseAsync(); }
        catch (Exception error) { Log.Write("media: " + error.Message); }
    }

    public async void Next()
    {
        if (_session is null) return;
        try { await _session.TrySkipNextAsync(); }
        catch (Exception error) { Log.Write("media: " + error.Message); }
    }

    public async void Previous()
    {
        if (_session is null) return;
        try { await _session.TrySkipPreviousAsync(); }
        catch (Exception error) { Log.Write("media: " + error.Message); }
    }

    public async void Seek(double seconds)
    {
        if (_session is null) return;
        try { await _session.TryChangePlaybackPositionAsync(TimeSpan.FromSeconds(Math.Max(0, seconds)).Ticks); }
        catch (Exception error) { Log.Write("media: " + error.Message); }
    }

    public void Dispose() => Attach(null);
}
