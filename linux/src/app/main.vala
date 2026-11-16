/* col: the island at the top of the screen. */

namespace Col {
    /* Translations beside the program first, so a tarball unpacked anywhere speaks its language. */
    string locale_dir () {
        var own = Paths.own_executable ();
        if (own != null) {
            var beside = Path.build_filename (Path.get_dirname (Path.get_dirname ((!) own)), "share", "locale");
            if (FileUtils.test (Path.build_filename (beside, "fr", "LC_MESSAGES", Config.GETTEXT_PACKAGE + ".mo"), FileTest.EXISTS)) {
                return beside;
            }
        }
        return Config.LOCALEDIR;
    }

    const string HELP = """usage: col-island [options] [col://link]

  --settings        open the settings
  --quit            quit the running Col
  --demo STATE      show the island in a state, with made-up content, for screenshots:
                    %s
  --version         print the version
""";

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (Config.GETTEXT_PACKAGE, locale_dir ());
        Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Config.GETTEXT_PACKAGE);

        string? demo = null;
        for (int i = 1; i < args.length; i++) {
            switch (args[i]) {
            case "--version":
                stdout.printf ("Col %s\n", Config.VERSION);
                return 0;
            case "--help":
            case "-h":
                stdout.printf (HELP, Demo.STATES);
                return 0;
            case "--demo":
                if (i + 1 >= args.length || !Demo.is_known (args[i + 1])) {
                    stderr.printf ("col-island: --demo takes one of: %s\n", Demo.STATES);
                    return 2;
                }
                demo = args[i + 1];
                break;
            default:
                break;
            }
        }

        // GNOME has no layer-shell: the island then runs under XWayland, where it can place its own window.
        if (Environment.get_variable ("GDK_BACKEND") == null && Environment.get_variable ("WAYLAND_DISPLAY") != null
            && Environment.get_variable ("DISPLAY") != null && !Platform.wayland_has_layer_shell ()) {
            Environment.set_variable ("GDK_BACKEND", "x11", true);
        }
        // The island is small and still most of the time: GTK's Cairo renderer draws it as well as the GPU would, without
        // loading a graphics driver, which would hold ten times the memory. GSK_RENDERER=ngl brings the GPU back.
        if (Environment.get_variable ("GSK_RENDERER") == null) {
            Environment.set_variable ("GSK_RENDERER", "cairo", true);
        }
        Environment.set_application_name ("Col");
        Environment.set_prgname (Config.APP_ID);

        var app = new App (demo);
        return app.run (args);
    }
}
