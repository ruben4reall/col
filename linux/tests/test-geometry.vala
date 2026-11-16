/* The island's sizes, its outline and its springs. */

using Col;

class Recorder : Object, PathSink {
    public double[] xs = {};
    public double[] ys = {};
    public int moves = 0;
    public int curves = 0;
    public int closes = 0;

    public void move_to (double x, double y) {
        moves++;
        xs += x;
        ys += y;
    }

    public void line_to (double x, double y) {
        xs += x;
        ys += y;
    }

    public void curve_to (double x1, double y1, double x2, double y2, double x3, double y3) {
        curves++;
        xs += x1;
        ys += y1;
        xs += x2;
        ys += y2;
        xs += x3;
        ys += y3;
    }

    public void close_path () {
        closes++;
    }
}

void test_frames () {
    var size = IslandSize.STANDARD;
    var hidden = Geometry.frame (IslandState.HIDDEN, 300, 200, size);
    var closed = Geometry.frame (IslandState.COLLAPSED, 300, 200, size);
    var peek = Geometry.frame (IslandState.PEEK, 300, 200, size);
    var open = Geometry.frame (IslandState.EXPANDED, 300, 200, size);
    // Floating, detached from the top edge, centred.
    assert_cmpfloat (closed.y, CompareOperator.EQ, Geometry.GAP);
    assert_cmpfloat (closed.cx, CompareOperator.EQ, 300);
    // A capsule: rounded on all four corners, the radius half its height.
    assert_cmpfloat (closed.height, CompareOperator.EQ, 34);
    assert_cmpfloat (closed.effective_radius (), CompareOperator.EQ, 17);
    assert_cmpfloat (peek.width, CompareOperator.GT, closed.width);
    assert_cmpfloat (peek.height, CompareOperator.GT, closed.height);
    assert_cmpfloat (hidden.width, CompareOperator.LT, closed.width);
    assert_cmpfloat (open.width, CompareOperator.EQ, 480);
    assert_cmpfloat (open.height, CompareOperator.EQ, 200);
    assert_cmpfloat (open.effective_radius (), CompareOperator.EQ, 32);
    // A long title never makes the closed island cover the screen.
    var long_one = Geometry.frame (IslandState.COLLAPSED, 300, 5000, size);
    assert_cmpfloat (long_one.width, CompareOperator.EQ, Geometry.MAX_COMPACT_WIDTH);
    assert_cmpfloat (Geometry.frame (IslandState.EXPANDED, 0, 0, IslandSize.LARGE).width, CompareOperator.EQ, 540);
    assert_true (IslandSize.from_key ("nonsense") == IslandSize.STANDARD);
    assert_cmpstr (IslandSize.COMPACT.to_key (), CompareOperator.EQ, "compact");
}

void test_envelopes () {
    int w, h;
    Geometry.envelope (IslandState.HIDDEN, IslandSize.STANDARD, Geometry.GAP, out w, out h);
    assert_cmpint (h, CompareOperator.LE, 4);
    int closed_w, closed_h;
    Geometry.envelope (IslandState.COLLAPSED, IslandSize.STANDARD, Geometry.GAP, out closed_w, out closed_h);
    int open_w, open_h;
    Geometry.envelope (IslandState.EXPANDED, IslandSize.STANDARD, Geometry.GAP, out open_w, out open_h);
    // Each surface holds its island and its shadow, and is even, so the centre falls on a pixel.
    var peek = Geometry.frame (IslandState.PEEK, 0, 5000, IslandSize.STANDARD);
    assert_cmpfloat (closed_w, CompareOperator.GE, peek.width);
    assert_cmpfloat (closed_h, CompareOperator.GE, peek.bottom ());
    assert_cmpfloat (open_w, CompareOperator.GE, 480 + Geometry.SHADOW * 2);
    assert_cmpfloat (open_h, CompareOperator.GE, Geometry.GAP + 200 + Geometry.SHADOW);
    assert_cmpint (closed_w % 2, CompareOperator.EQ, 0);
    assert_cmpint (open_w % 2, CompareOperator.EQ, 0);
}

void test_outline () {
    foreach (var state in new IslandState[] { IslandState.COLLAPSED, IslandState.PEEK, IslandState.EXPANDED }) {
        var frame = Geometry.frame (state, 250, 180, IslandSize.STANDARD);
        var recorder = new Recorder ();
        Geometry.outline (frame, recorder);
        // One closed shape of four straight edges and four eased corners, whatever the state.
        assert_cmpint (recorder.moves, CompareOperator.EQ, 1);
        assert_cmpint (recorder.curves, CompareOperator.EQ, 4);
        assert_cmpint (recorder.closes, CompareOperator.EQ, 1);
        double min_x = double.MAX, max_x = -double.MAX, min_y = double.MAX, max_y = -double.MAX;
        for (int i = 0; i < recorder.xs.length; i++) {
            min_x = double.min (min_x, recorder.xs[i]);
            max_x = double.max (max_x, recorder.xs[i]);
            min_y = double.min (min_y, recorder.ys[i]);
            max_y = double.max (max_y, recorder.ys[i]);
        }
        // It stays inside its frame and touches all four sides.
        assert_cmpfloat (min_x, CompareOperator.EQ, frame.left ());
        assert_cmpfloat (max_x, CompareOperator.EQ, frame.right ());
        assert_cmpfloat (min_y, CompareOperator.EQ, frame.y);
        assert_cmpfloat (max_y, CompareOperator.EQ, frame.bottom ());
        // Symmetric about its centre line.
        for (int i = 0; i < recorder.xs.length; i++) {
            bool mirrored = false;
            for (int j = 0; j < recorder.xs.length; j++) {
                if (Math.fabs ((frame.cx - recorder.xs[i]) - (recorder.xs[j] - frame.cx)) < 1e-9
                    && Math.fabs (recorder.ys[i] - recorder.ys[j]) < 1e-9) {
                    mirrored = true;
                }
            }
            assert_true (mirrored);
        }
    }
}

void test_springs () {
    var spring = new Spring (0);
    spring.animate_to (100, Motion.opening ());
    double peak = 0;
    int frames = 0;
    while (spring.step (1.0 / 60) && frames < 600) {
        peak = double.max (peak, spring.value);
        frames++;
    }
    // Opening overshoots a little, then settles, in well under two seconds.
    assert_cmpfloat (peak, CompareOperator.GT, 100);
    assert_cmpfloat (peak, CompareOperator.LT, 110);
    assert_cmpint (frames, CompareOperator.LT, 120);
    assert_cmpfloat (spring.value, CompareOperator.EQ, 100);
    // Closing does not bounce.
    var closing = new Spring (100);
    closing.animate_to (0, Motion.closing ());
    double lowest = 100;
    while (closing.step (1.0 / 60)) {
        lowest = double.min (lowest, closing.value);
    }
    assert_cmpfloat (lowest, CompareOperator.GE, -0.01);
    // A late frame does not make it explode.
    var late = new Spring (0);
    late.animate_to (50, Motion.peeking ());
    late.step (0.5);
    assert_true (late.value.is_finite () && Math.fabs (late.value) < 200);
    // At rest, it does not ask for frames.
    assert_false (new Spring (3).step (1.0 / 60));
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/geometry/frames", test_frames);
    Test.add_func ("/geometry/envelopes", test_envelopes);
    Test.add_func ("/geometry/outline", test_outline);
    Test.add_func ("/geometry/springs", test_springs);
    return Test.run ();
}
