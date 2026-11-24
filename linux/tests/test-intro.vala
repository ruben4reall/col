/* The intro's score: the Mac's times, bars that ring with their bell, waves that leave and fade. */

using Col;

void test_score () {
    assert (IntroScore.TRACE_START < IntroScore.TRACE_END);
    assert (IntroScore.SWELL == IntroScore.bell (0));
    assert (IntroScore.bell (0) == 0.42 && IntroScore.bell (3) == 0.87);
    assert (IntroScore.TUCK < IntroScore.END);
}

void test_bars () {
    for (int bar = 0; bar < 4; bar++) {
        for (int step = 0; step <= 300; step++) {
            double level = IntroScore.bar_level (bar, step / 100.0);
            assert (level >= IntroScore.BAR_REST - 1e-9 && level <= 1 + 1e-9);
        }
        assert (IntroScore.bar_level (bar, IntroScore.bell (bar) + 0.03) > IntroScore.bar_level (bar, IntroScore.bell (bar) - 0.01));
    }
    assert (IntroScore.bar_level (0, 0) == IntroScore.BAR_REST);
}

void test_waves () {
    assert (IntroScore.wave_progress (0, IntroScore.bell (0) - 0.01) < 0);
    assert (IntroScore.wave_progress (0, IntroScore.bell (0)) == 0);
    assert (IntroScore.wave_progress (0, IntroScore.bell (0) + IntroScore.WAVE_DURATION + 0.01) < 0);
    assert (IntroScore.ease (0.5) > 0.5);
    assert (IntroScore.wave_opacity (0) == 0);
    assert (Math.fabs (IntroScore.wave_opacity (0.1) - 1) < 1e-9);
    assert (Math.fabs (IntroScore.wave_opacity (1)) < 1e-9);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/intro/score", test_score);
    Test.add_func ("/intro/bars", test_bars);
    Test.add_func ("/intro/waves", test_waves);
    return Test.run ();
}
