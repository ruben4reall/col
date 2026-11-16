/* Where Col keeps its files, following the XDG base directories. */

namespace Col.Paths {
    /* The socket colctl and the agents' hooks talk to. COL_SOCKET moves it, as on the Mac, so a development build can
     * run beside the installed one. */
    public string socket_path () {
        var custom = Environment.get_variable ("COL_SOCKET");
        if (custom != null && custom != "") {
            return custom;
        }
        return Path.build_filename (Environment.get_user_runtime_dir (), "col", "col.sock");
    }

    public string config_dir () {
        return Path.build_filename (Environment.get_user_config_dir (), "col");
    }

    public string cache_dir () {
        return Path.build_filename (Environment.get_user_cache_dir (), "col");
    }

    public string data_dir () {
        return Path.build_filename (Environment.get_user_data_dir (), "col");
    }

    /* $HOME first: GLib keeps the first home it finds for the life of the process. */
    public string home () {
        var variable = Environment.get_variable ("HOME");
        return variable != null && variable != "" ? (!) variable : Environment.get_home_dir ();
    }

    /* "~/x" in the user's home. */
    public string expand (string path) {
        if (path == "~") {
            return home ();
        }
        if (path.has_prefix ("~/")) {
            return Path.build_filename (home (), path.substring (2));
        }
        return path;
    }

    /* The file of the running program, links resolved. */
    public string? own_executable () {
        try {
            return FileUtils.read_link ("/proc/self/exe");
        } catch (FileError e) {
            return null;
        }
    }

    /* A hex SHA-256 of a text, for file names in the caches. */
    public string digest (string text) {
        return Checksum.compute_for_string (ChecksumType.SHA256, text);
    }
}
