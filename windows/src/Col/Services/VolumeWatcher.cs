using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace Col.Services;

/// <summary>
/// The system volume, from Core Audio: the default output tells Col each time its volume or mute changes, from the
/// keyboard, the volume flyout or any app. Windows' own flyout still shows; Col shows its gauge in the island beside it.
/// </summary>
internal sealed class VolumeWatcher : IDisposable
{
    private readonly Dispatcher _dispatcher;
    private IMMDeviceEnumerator? _enumerator;
    private IAudioEndpointVolume? _endpoint;
    private readonly VolumeCallback _callback;
    private readonly DeviceCallback _devices;
    private float _lastLevel = -1;
    private bool _lastMuted;

    /// <summary>The level, from 0 to 1, and whether the sound is muted.</summary>
    public event Action<double, bool>? Changed;

    public VolumeWatcher(Dispatcher dispatcher)
    {
        _dispatcher = dispatcher;
        _callback = new VolumeCallback(this);
        _devices = new DeviceCallback(this);
    }

    public void Start()
    {
        try
        {
            _enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
            _enumerator.RegisterEndpointNotificationCallback(_devices);
            AttachDefault();
        }
        catch (Exception error)
        {
            Log.Write("volume: " + error.Message);
        }
    }

    private void AttachDefault()
    {
        Detach();
        if (_enumerator is null) return;
        // eRender, eMultimedia.
        if (_enumerator.GetDefaultAudioEndpoint(0, 1, out var device) != 0 || device is null) return;
        var iid = typeof(IAudioEndpointVolume).GUID;
        // CLSCTX_ALL.
        if (device.Activate(ref iid, 23, IntPtr.Zero, out var activated) != 0) return;
        _endpoint = (IAudioEndpointVolume)activated;
        _endpoint.GetMasterVolumeLevelScalar(out _lastLevel);
        _endpoint.GetMute(out _lastMuted);
        _endpoint.RegisterControlChangeNotify(_callback);
        Marshal.ReleaseComObject(device);
    }

    private void Detach()
    {
        if (_endpoint is null) return;
        try { _endpoint.UnregisterControlChangeNotify(_callback); }
        catch (COMException) { }
        Marshal.ReleaseComObject(_endpoint);
        _endpoint = null;
    }

    /// <summary>Called on a Core Audio thread.</summary>
    private void OnNotify(IntPtr data)
    {
        if (data == IntPtr.Zero) return;
        // AUDIO_VOLUME_NOTIFICATION_DATA: a GUID, then BOOL bMuted, then float fMasterVolume.
        var muted = Marshal.ReadInt32(data, 16) != 0;
        var level = BitConverter.Int32BitsToSingle(Marshal.ReadInt32(data, 20));
        _dispatcher.BeginInvoke(() =>
        {
            if (Math.Abs(level - _lastLevel) < 0.0005f && muted == _lastMuted) return;
            _lastLevel = level;
            _lastMuted = muted;
            Changed?.Invoke(level, muted);
        });
    }

    private void OnDefaultChanged() => _dispatcher.BeginInvoke(AttachDefault);

    public void Dispose()
    {
        Detach();
        if (_enumerator is null) return;
        try { _enumerator.UnregisterEndpointNotificationCallback(_devices); }
        catch (COMException) { }
        Marshal.ReleaseComObject(_enumerator);
        _enumerator = null;
    }

    [ComVisible(true)]
    private sealed class VolumeCallback(VolumeWatcher owner) : IAudioEndpointVolumeCallback
    {
        public int OnNotify(IntPtr notifyData)
        {
            owner.OnNotify(notifyData);
            return 0;
        }
    }

    [ComVisible(true)]
    private sealed class DeviceCallback(VolumeWatcher owner) : IMMNotificationClient
    {
        public int OnDeviceStateChanged(string deviceId, int newState) => 0;
        public int OnDeviceAdded(string deviceId) => 0;
        public int OnDeviceRemoved(string deviceId) => 0;

        public int OnDefaultDeviceChanged(int flow, int role, string? defaultDeviceId)
        {
            // The default output for media changed: follow it.
            if (flow == 0 && role == 1) owner.OnDefaultChanged();
            return 0;
        }

        public int OnPropertyValueChanged(string deviceId, PropertyKey key) => 0;
    }
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
internal class MMDeviceEnumeratorComObject { }

[StructLayout(LayoutKind.Sequential)]
internal struct PropertyKey
{
    public Guid FormatId;
    public int PropertyId;
}

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDeviceEnumerator
{
    [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice? endpoint);
    [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice? device);
    [PreserveSig] int RegisterEndpointNotificationCallback(IMMNotificationClient client);
    [PreserveSig] int UnregisterEndpointNotificationCallback(IMMNotificationClient client);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDevice
{
    [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object activated);
    [PreserveSig] int OpenPropertyStore(int access, out IntPtr store);
    [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
    [PreserveSig] int GetState(out int state);
}

[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioEndpointVolume
{
    [PreserveSig] int RegisterControlChangeNotify(IAudioEndpointVolumeCallback notify);
    [PreserveSig] int UnregisterControlChangeNotify(IAudioEndpointVolumeCallback notify);
    [PreserveSig] int GetChannelCount(out uint count);
    [PreserveSig] int SetMasterVolumeLevel(float levelDb, ref Guid context);
    [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid context);
    [PreserveSig] int GetMasterVolumeLevel(out float levelDb);
    [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
    [PreserveSig] int SetChannelVolumeLevel(uint channel, float levelDb, ref Guid context);
    [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);
    [PreserveSig] int GetChannelVolumeLevel(uint channel, out float levelDb);
    [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
    [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
    [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
}

[ComImport, Guid("657804FA-D6AD-4496-8A60-352752AF4F89"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioEndpointVolumeCallback
{
    [PreserveSig] int OnNotify(IntPtr notifyData);
}

[ComImport, Guid("7991EEC9-7E89-4D85-8390-6C703CEC60C0"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMNotificationClient
{
    [PreserveSig] int OnDeviceStateChanged([MarshalAs(UnmanagedType.LPWStr)] string deviceId, int newState);
    [PreserveSig] int OnDeviceAdded([MarshalAs(UnmanagedType.LPWStr)] string deviceId);
    [PreserveSig] int OnDeviceRemoved([MarshalAs(UnmanagedType.LPWStr)] string deviceId);
    [PreserveSig] int OnDefaultDeviceChanged(int flow, int role, [MarshalAs(UnmanagedType.LPWStr)] string? defaultDeviceId);
    [PreserveSig] int OnPropertyValueChanged([MarshalAs(UnmanagedType.LPWStr)] string deviceId, PropertyKey key);
}
