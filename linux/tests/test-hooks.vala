/* Connecting agents: Col's hooks added to and removed from an agent's settings, everything else kept as it was. Runs
 * in a home of its own, so nothing of the user's is read or written. */

using Col;

string home;

void fresh_home () {
    try {
        home = DirUtils.make_tmp ("col-hooks-XXXXXX");
    } catch (FileError e) {
        error ("%s", e.message);
    }
    Environment.set_variable ("HOME", home, true);
    DirUtils.create_with_parents (Path.build_filename (home, ".claude"), 0700);
}

string read_file (string path) {
    string text;
    try {
        FileUtils.get_contents (path, out text);
    } catch (FileError e) {
        error ("%s", e.message);
    }
    return text;
}

void write_file (string path, string text) {
    try {
        FileUtils.set_contents (path, text);
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

string edit_ok (HookAgent agent, string? path, bool install, string? colctl) {
    try {
        return Hooks.edit (agent, path, install, colctl);
    } catch (HooksError e) {
        error ("%s", e.message);
    }
}

int count_col_groups (Json.Object settings, string event) {
    var groups = JsonText.get_array (JsonText.get_object (settings, "hooks"), event);
    if (groups == null) {
        return 0;
    }
    int count = 0;
    for (uint i = 0; i < groups.get_length (); i++) {
        if (Hooks.is_col_hook (groups.get_element (i))) {
            count++;
        }
    }
    return count;
}

const string USER_SETTINGS = """{
  "model": "opus",
  "temperature": 0.1,
  "env": {
    "PATH_NOTE": "a/b é"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/bin/audit.sh"
          }
        ]
      }
    ]
  }
}
""";

void test_install_keeps_everything () {
    fresh_home ();
    var agent = HookAgent.named ("claude");
    var path = Path.build_filename (home, ".claude", "settings.json");
    write_file (path, USER_SETTINGS);
    FileUtils.chmod (path, 0644);
    var message = edit_ok ((!) agent, null, true, null);
    assert_true (message.contains ("hooks installed"));
    var text = read_file (path);
    var settings = JsonText.parse_object (text);
    assert_nonnull (settings);
    // The user's own keys, values and hook are all still there, in their order, unchanged.
    assert_cmpstr (JsonText.get_string (settings, "model"), CompareOperator.EQ, "opus");
    assert_true (text.contains ("\"temperature\": 0.1,"));
    assert_true (text.contains ("\"PATH_NOTE\": \"a/b é\""));
    assert_true (text.index_of ("\"model\"") < text.index_of ("\"temperature\"") && text.index_of ("\"env\"") < text.index_of ("\"hooks\""));
    var pre = JsonText.get_array (JsonText.get_object (settings, "hooks"), "PreToolUse");
    assert_cmpint ((int) pre.get_length (), CompareOperator.EQ, 2);
    assert_cmpstr (JsonText.get_string (pre.get_object_element (0), "matcher"), CompareOperator.EQ, "Bash");
    // Col's entries, for every event it follows, waiting long enough for an answer to a permission request.
    foreach (var event in agent.events) {
        assert_cmpint (count_col_groups ((!) settings, event.name), CompareOperator.EQ, 1);
    }
    var request = JsonText.get_array (JsonText.get_object (settings, "hooks"), "PermissionRequest").get_object_element (0);
    var hook = JsonText.get_array (request, "hooks").get_object_element (0);
    assert_cmpstr (JsonText.get_string (hook, "command"), CompareOperator.EQ, "\"$HOME/.local/bin/colctl\" hook");
    assert_cmpint ((int) hook.get_int_member ("timeout"), CompareOperator.EQ, 120);
    assert_cmpstr (JsonText.get_string (request, "matcher"), CompareOperator.EQ, "*");
    // The file keeps its mode; the backup is the user's alone and holds the file as it was.
    Posix.Stat status;
    Posix.stat (path, out status);
    assert_cmpint ((int) (status.st_mode & 0777), CompareOperator.EQ, 0644);
    Posix.stat (path + ".col-backup", out status);
    assert_cmpint ((int) (status.st_mode & 0777), CompareOperator.EQ, 0600);
    assert_cmpstr (read_file (path + ".col-backup"), CompareOperator.EQ, USER_SETTINGS);
    assert_true (Hooks.is_connected ((!) agent));

    // Installing twice adds nothing.
    edit_ok ((!) agent, null, true, null);
    foreach (var event in agent.events) {
        assert_cmpint (count_col_groups ((!) JsonText.parse_object (read_file (path)), event.name), CompareOperator.EQ, 1);
    }

    // Uninstalling gives back the user's settings.
    edit_ok ((!) agent, null, false, null);
    var after = JsonText.parse_object (read_file (path));
    assert_false (Hooks.is_connected ((!) agent));
    assert_cmpstr (JsonText.compact (wrap (after)), CompareOperator.EQ, JsonText.compact (wrap (JsonText.parse_object (USER_SETTINGS))));
}

Json.Node wrap (Json.Object? object) {
    var node = new Json.Node (Json.NodeType.OBJECT);
    node.set_object ((!) object);
    return node;
}

void test_new_file_and_codex () {
    fresh_home ();
    DirUtils.create_with_parents (Path.build_filename (home, ".codex"), 0700);
    var codex = HookAgent.named ("codex");
    var message = edit_ok ((!) codex, null, true, null);
    assert_true (message.contains ("/hooks"));
    var path = Path.build_filename (home, ".codex", "hooks.json");
    var settings = JsonText.parse_object (read_file (path));
    var hook = JsonText.get_array (JsonText.get_array (JsonText.get_object (settings, "hooks"), "PermissionRequest").get_object_element (0), "hooks").get_object_element (0);
    assert_cmpstr (JsonText.get_string (hook, "command"), CompareOperator.EQ, "\"$HOME/.local/bin/colctl\" hook --agent codex");
    // Codex takes no tool matcher.
    assert_null (JsonText.get_string (JsonText.get_array (JsonText.get_object (settings, "hooks"), "PreToolUse").get_object_element (0), "matcher"));
    Posix.Stat status;
    Posix.stat (path, out status);
    assert_cmpint ((int) (status.st_mode & 0777), CompareOperator.EQ, 0600);
    // Removing every hook from a file that held only Col's leaves an empty object, not an empty "hooks".
    edit_ok ((!) codex, null, false, null);
    assert_cmpstr (read_file (path).strip (), CompareOperator.EQ, "{}");
    // Nothing to remove where there is no file.
    var claude = HookAgent.named ("claude");
    assert_true (edit_ok ((!) claude, null, false, null).contains ("nothing to remove"));
}

void test_invalid_json_is_left_alone () {
    fresh_home ();
    var path = Path.build_filename (home, ".claude", "settings.json");
    write_file (path, "{ not json");
    try {
        Hooks.edit ((!) HookAgent.named ("claude"), null, true, null);
        assert_not_reached ();
    } catch (HooksError e) {
        assert_true (e.message.contains ("not valid JSON"));
    }
    assert_cmpstr (read_file (path), CompareOperator.EQ, "{ not json");
    assert_false (FileUtils.test (path + ".col-backup", FileTest.EXISTS));
}

void test_links_are_followed () {
    // A settings file kept by a dotfile manager is a link: the link stays, the file it points to is edited.
    fresh_home ();
    var real = Path.build_filename (home, "dotfiles-settings.json");
    write_file (real, "{\"model\": \"opus\"}\n");
    var path = Path.build_filename (home, ".claude", "settings.json");
    FileUtils.symlink (real, path);
    edit_ok ((!) HookAgent.named ("claude"), null, true, null);
    assert_true (FileUtils.test (path, FileTest.IS_SYMLINK));
    assert_true (Hooks.mentions_col (read_file (real)));
}

void test_recognises_hooks_written_on_a_mac () {
    assert_true (Hooks.calls_col ("\"$HOME/.local/bin/colctl\" hook"));
    assert_true (Hooks.calls_col ("\"$HOME/.local/bin/colctl\" hook --agent codex"));
    assert_true (Hooks.calls_col ("\"$HOME/.local/bin/islet\" hook"));
    assert_false (Hooks.calls_col ("~/bin/audit.sh"));
    assert_false (Hooks.calls_col (null));
}

void test_command_link () {
    fresh_home ();
    var tool = Path.build_filename (home, "colctl-real");
    write_file (tool, "#!/bin/sh\n");
    FileUtils.chmod (tool, 0755);
    Hooks.link_command (tool);
    var link = Path.build_filename (home, ".local", "bin", "colctl");
    assert_true (FileUtils.test (link, FileTest.IS_SYMLINK));
    assert_cmpstr (Posix.realpath (link), CompareOperator.EQ, Posix.realpath (tool));
    // A command of the user's own at that place is never replaced.
    FileUtils.unlink (link);
    write_file (link, "mine");
    Hooks.link_command (tool);
    assert_cmpstr (read_file (link), CompareOperator.EQ, "mine");
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/hooks/install-keeps-everything", test_install_keeps_everything);
    Test.add_func ("/hooks/new-file-and-codex", test_new_file_and_codex);
    Test.add_func ("/hooks/invalid-json-is-left-alone", test_invalid_json_is_left_alone);
    Test.add_func ("/hooks/links-are-followed", test_links_are_followed);
    Test.add_func ("/hooks/recognises-mac-hooks", test_recognises_hooks_written_on_a_mac);
    Test.add_func ("/hooks/command-link", test_command_link);
    return Test.run ();
}
