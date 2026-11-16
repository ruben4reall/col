using System.IO;
using System.Reflection;

namespace Col.Services;

/// <summary>Where Col keeps its few files, all under %LOCALAPPDATA%\Col.</summary>
internal static class AppPaths
{
    public static string Folder { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Col");

    public static string Settings => Path.Combine(Folder, "settings.json");

    /// <summary>LRCLIB's answers, a small file per track.</summary>
    public static string Lyrics => Path.Combine(Folder, "lyrics");

    public static string LogFile => Path.Combine(Folder, "col.log");

    /// <summary>colctl.exe, installed beside Col.exe.</summary>
    public static string Colctl => Path.Combine(AppContext.BaseDirectory, "colctl.exe");

    public static string Executable => Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "Col.exe");

    public static string Version { get; } =
        Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "3.0.0";
}

/// <summary>A short log of what went wrong, for bug reports: never what the user plays, copies or types.</summary>
internal static class Log
{
    private static readonly object Lock = new();

    public static void Write(string message)
    {
        try
        {
            lock (Lock)
            {
                Directory.CreateDirectory(AppPaths.Folder);
                var file = new FileInfo(AppPaths.LogFile);
                // A small log: started afresh past 256 KB.
                if (file.Exists && file.Length > 256 * 1024) file.Delete();
                File.AppendAllText(AppPaths.LogFile, $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss} {message}{Environment.NewLine}");
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }
}
