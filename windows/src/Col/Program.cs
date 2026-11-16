using Col.Services;

namespace Col;

/// <summary>Col's entry point: WPF's own, wrapped so that anything that stops Col before its window shows is logged.</summary>
internal static class Program
{
    [STAThread]
    public static int Main()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, args) => Log.Write("fatal: " + args.ExceptionObject);
        try
        {
            var app = new App();
            app.InitializeComponent();
            return app.Run();
        }
        catch (Exception error)
        {
            Log.Write("fatal: " + error);
            Console.Error.WriteLine(error);
            throw;
        }
    }
}
