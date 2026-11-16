using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using Col.Core;

namespace Col.Services;

/// <summary>
/// The local API on a named pipe, <c>\\.\pipe\col-&lt;SID&gt;</c>, that only the user's own account can open: its
/// access list names that account alone and refuses anyone coming over the network. Each connection carries one HTTP
/// request; a permission request keeps its connection open until the user answers in the island.
/// </summary>
internal sealed class PipeServer(ControlApi api) : IDisposable
{
    private readonly CancellationTokenSource _stop = new();

    public static string Name
    {
        get
        {
            using var identity = WindowsIdentity.GetCurrent();
            return Ipc.PipeName(identity.User?.Value ?? "unknown", Environment.GetEnvironmentVariable("COL_PIPE"));
        }
    }

    public void Start() => _ = Task.Run(AcceptAsync);

    private static PipeSecurity Security()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var user = identity.User ?? throw new InvalidOperationException("no user");
        var security = new PipeSecurity();
        security.SetOwner(user);
        security.AddAccessRule(new PipeAccessRule(user,
            PipeAccessRights.ReadWrite | PipeAccessRights.CreateNewInstance | PipeAccessRights.Synchronize, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null),
            PipeAccessRights.FullControl, AccessControlType.Deny));
        return security;
    }

    private async Task AcceptAsync()
    {
        var name = Name;
        var security = Security();
        var first = true;
        while (!_stop.IsCancellationRequested)
        {
            NamedPipeServerStream pipe;
            try
            {
                var options = PipeOptions.Asynchronous | (first ? PipeOptions.FirstPipeInstance : PipeOptions.None);
                pipe = NamedPipeServerStreamAcl.Create(name, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                    PipeTransmissionMode.Byte, options, 0, 0, security);
                first = false;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // Another program holds the name: Col keeps running, without its API.
                Log.Write("pipe: " + error.Message);
                return;
            }
            try
            {
                await pipe.WaitForConnectionAsync(_stop.Token).ConfigureAwait(false);
            }
            catch (Exception error) when (error is OperationCanceledException or IOException or ObjectDisposedException)
            {
                await pipe.DisposeAsync().ConfigureAwait(false);
                if (_stop.IsCancellationRequested) return;
                continue;
            }
            _ = Task.Run(() => ServeAsync(pipe));
        }
    }

    private async Task ServeAsync(NamedPipeServerStream pipe)
    {
        await using var _ = pipe;
        try
        {
            using var reading = CancellationTokenSource.CreateLinkedTokenSource(_stop.Token);
            reading.CancelAfter(TimeSpan.FromSeconds(5));
            var request = await HttpWire.ReadRequestAsync(pipe, reading.Token).ConfigureAwait(false);
            var response = request is null ? HttpResponse.Error("bad request", 400) : await api.HandleAsync(request).ConfigureAwait(false);
            await pipe.WriteAsync(HttpWire.FormatResponse(response), _stop.Token).ConfigureAwait(false);
            await pipe.FlushAsync(_stop.Token).ConfigureAwait(false);
            // The answer stays in the pipe until the other end has read it: closing earlier would throw it away.
            pipe.WaitForPipeDrain();
        }
        catch (Exception error) when (error is IOException or OperationCanceledException or ObjectDisposedException or InvalidOperationException)
        {
            // The other end went away, or Col is quitting.
        }
    }

    public void Dispose()
    {
        _stop.Cancel();
        _stop.Dispose();
    }
}
