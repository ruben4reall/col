using System.Windows;
using System.Windows.Controls;
using Col.Core;
using Col.Localization;

namespace Col.Island;

/// <summary>
/// A coding agent asks for permission: who asks, the whole command, Allow and Deny. What Allow approves is what the card
/// shows; a command too long to check here is left to the terminal, and Allow is off.
/// </summary>
internal partial class PermissionCard : UserControl
{
    private Hub? _hub;
    private PendingRequest? _request;

    public PermissionCard()
    {
        InitializeComponent();
        Allow.Click += (_, _) => Answer(Decision.Allow);
        Deny.Click += (_, _) => Answer(Decision.Deny);
    }

    public void Bind(Hub hub) => _hub = hub;

    public bool HasRequest => _request is not null;

    /// <summary>Shows the oldest request waiting; false when none waits.</summary>
    public bool Refresh()
    {
        if (_hub is null) return false;
        var pending = _hub.Agents.Pending;
        _request = pending.FirstOrDefault();
        if (_request is not { } request) return false;
        Logo.Content = CompactViews.AgentLogo(request.Agent ?? request.Project, 22);
        Heading.Text = L.Format("Card_Heading", request.Agent ?? L.Get("Card_AnAgent"), request.Project);
        Tool.Text = string.IsNullOrEmpty(request.Tool) ? L.Get("Card_Tool") : request.Tool;
        Queue.Text = pending.Count > 1 ? L.Format("Card_More", pending.Count - 1) : "";
        Command.Text = request.Detail?.Shown ?? request.Summary;
        var allowed = AgentCenter.CanAllow(request);
        Allow.IsEnabled = allowed;
        Note.Visibility = allowed ? Visibility.Collapsed : Visibility.Visible;
        return true;
    }

    private void Answer(Decision decision)
    {
        if (_hub is null || _request is null) return;
        _hub.Decide(_request.Id, decision);
    }
}
