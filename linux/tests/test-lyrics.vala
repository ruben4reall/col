/* LRC parsing and the line being sung: the same cases as the Mac's LyricsTests. */

using Col;

string texts (Lyrics lyrics, bool skip_pauses = false) {
    var parts = new GenericArray<string> ();
    foreach (var line in lyrics.lines) {
        if (skip_pauses && line.is_pause ()) {
            continue;
        }
        parts.add ("[" + line.text + "]");
    }
    return string.joinv ("", parts.data);
}

void test_timed_lines_in_order () {
    var lyrics = Lyrics.parse ("[ar:Someone]\n[ti:A Song]\n[00:12.50]Second line\n[00:01.00]First line\n[00:20.00]\n");
    assert_nonnull (lyrics);
    assert_true (lyrics.is_synced);
    // The first line is sung in about two seconds: the nine that follow are a pause.
    assert_cmpstr (texts (lyrics), CompareOperator.EQ, "[First line][][Second line][]");
    assert_cmpfloat (lyrics.lines[0].time, CompareOperator.EQ, 1);
    assert_cmpfloat (lyrics.lines[1].time, CompareOperator.EQ, 3);
    assert_cmpfloat (lyrics.lines[2].time, CompareOperator.EQ, 12.5);
    assert_cmpfloat (lyrics.lines[3].time, CompareOperator.EQ, 20);
}

void test_several_times () {
    var lyrics = Lyrics.parse ("[00:05.00][00:30.00]Chorus\n[00:10.00]Verse");
    assert_cmpstr (texts (lyrics, true), CompareOperator.EQ, "[Chorus][Verse][Chorus]");
}

void test_offset () {
    var lyrics = Lyrics.parse ("[offset:+500]\n[00:02.00]Hello");
    assert_cmpfloat (lyrics.lines[0].time, CompareOperator.EQ, 1.5);
}

void test_word_timing () {
    var lyrics = Lyrics.parse ("[00:12.00]<00:12.10> Hello <00:12.60> world");
    LyricLine? sung = null;
    foreach (var line in lyrics.lines) {
        if (!line.is_pause ()) {
            sung = line;
        }
    }
    assert_nonnull (sung);
    assert_cmpstr (sung.text, CompareOperator.EQ, "Hello world");
    assert_cmpint (sung.word_count, CompareOperator.EQ, 2);
    assert_cmpfloat (sung.last_word, CompareOperator.EQ, 12.6);
}

void test_long_gaps () {
    var lyrics = Lyrics.parse ("[00:10.00]Late start\n[00:12.00]Close\n[00:40.00]After a solo");
    var pauses = new StringBuilder ();
    foreach (var line in lyrics.lines) {
        pauses.append (line.is_pause () ? "p" : "l");
    }
    assert_cmpstr (pauses.str, CompareOperator.EQ, "pllpl");
    assert_cmpfloat (lyrics.lines[0].time, CompareOperator.EQ, 0);
}

void test_line_being_sung () {
    var lyrics = Lyrics.parse ("[00:01.00]a\n[00:03.00]b\n[00:05.00]c");
    assert_cmpint (lyrics.index_at (0.5), CompareOperator.EQ, -1);
    assert_cmpint (lyrics.index_at (1), CompareOperator.EQ, 0);
    assert_cmpint (lyrics.index_at (4.9), CompareOperator.EQ, 1);
    assert_cmpint (lyrics.index_at (500), CompareOperator.EQ, 2);
    assert_cmpfloat (lyrics.next_change (3), CompareOperator.EQ, 5);
    assert_cmpfloat (lyrics.next_change (5), CompareOperator.EQ, -1);
}

void test_timestamps () {
    double t;
    assert_true (Lyrics.timestamp ("01:02", out t) && t == 62);
    assert_true (Lyrics.timestamp ("01:02.5", out t) && t == 62.5);
    assert_true (Lyrics.timestamp ("01:02.250", out t) && t == 62.25);
    assert_true (Lyrics.timestamp ("1:01:02.00", out t) && t == 3662);
    assert_true (Lyrics.timestamp ("01:02,5", out t) && t == 62.5);
    assert_false (Lyrics.timestamp ("ar:Someone", out t));
    assert_false (Lyrics.timestamp ("01:xx", out t));
    // Times no track could reach are not read.
    assert_false (Lyrics.timestamp ("00:inf", out t));
    assert_false (Lyrics.timestamp ("00:infinity", out t));
    assert_false (Lyrics.timestamp ("00:nan", out t));
    assert_false (Lyrics.timestamp ("00:1e999", out t));
    assert_false (Lyrics.timestamp ("99999999999999999999:00", out t));
    assert_false (Lyrics.timestamp ("24:00:00", out t));
    assert_true (Lyrics.timestamp ("23:59:59", out t) && t == 86399);
}

void test_damaged_lines () {
    var lyrics = Lyrics.parse ("[00:01.00] a\n[00:inf] b\n[00:1e999] c\n[00:03.00] <00:inf> d");
    assert_cmpstr (texts (lyrics, true), CompareOperator.EQ, "[a][d]");
    foreach (var offset in new string[] { "-1e400", "1e400", "nan", "-99999999999" }) {
        var shifted = Lyrics.parse ("[offset:%s]\n[00:01.00] a".printf (offset));
        assert_cmpfloat (shifted.lines[0].time, CompareOperator.EQ, 1);
    }
}

void test_wait () {
    var lyrics = new Lyrics ();
    lyrics.is_synced = true;
    lyrics.lines.add (new LyricLine (1, "a"));
    lyrics.lines.add (new LyricLine (3, "b"));
    lyrics.lines.add (new LyricLine (1e22, "c"));
    // A little early, at the rate the track plays.
    assert_true (Math.fabs (lyrics.wait_after (1, 1) - 1.88) < 0.001);
    assert_true (Math.fabs (lyrics.wait_after (1, 2) - 0.88) < 0.001);
    assert_cmpfloat (lyrics.wait_after (2.99, 1), CompareOperator.EQ, 0.05);
    assert_cmpfloat (lyrics.wait_after (3, 1), CompareOperator.EQ, 3600);
    assert_cmpfloat (lyrics.wait_after (1e22, 1), CompareOperator.EQ, -1);
    assert_cmpfloat (lyrics.wait_after (double.NAN, 1), CompareOperator.EQ, -1);
}

void test_plain () {
    var lyrics = Lyrics.plain ("One\nTwo");
    assert_nonnull (lyrics);
    assert_false (lyrics.is_synced);
    assert_cmpint (lyrics.index_at (10), CompareOperator.EQ, -1);
    assert_null (Lyrics.plain (" \n "));
    assert_null (Lyrics.parse ("no timing at all"));
}

void test_queries () {
    var query = new LyricsQuery ("Terrasser (Remastered 2020)", "Gradur feat. Heuss", "", 181);
    assert_cmpstr (query.clean_title (), CompareOperator.EQ, "Terrasser");
    assert_cmpstr (query.main_artist (), CompareOperator.EQ, "Gradur");
    assert_cmpstr (query.cache_key (), CompareOperator.EQ, new LyricsQuery ("terrasser", "GRADUR", "x", 181.2).cache_key ());
    assert_true (query.matches (182.5));
    assert_false (query.matches (190));
    assert_true (query.matches (-1));
    assert_cmpstr (new LyricsQuery ("Song - Live at Wembley", "A & B", "", 0).clean_title (), CompareOperator.EQ, "Song");
    assert_cmpstr (new LyricsQuery ("Song", "A & B", "", 0).main_artist (), CompareOperator.EQ, "A");
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/lyrics/timed-lines-in-order", test_timed_lines_in_order);
    Test.add_func ("/lyrics/several-times", test_several_times);
    Test.add_func ("/lyrics/offset", test_offset);
    Test.add_func ("/lyrics/word-timing", test_word_timing);
    Test.add_func ("/lyrics/long-gaps", test_long_gaps);
    Test.add_func ("/lyrics/line-being-sung", test_line_being_sung);
    Test.add_func ("/lyrics/timestamps", test_timestamps);
    Test.add_func ("/lyrics/damaged-lines", test_damaged_lines);
    Test.add_func ("/lyrics/wait", test_wait);
    Test.add_func ("/lyrics/plain", test_plain);
    Test.add_func ("/lyrics/queries", test_queries);
    return Test.run ();
}
