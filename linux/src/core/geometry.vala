/* The island's sizes and outline, and the springs that move it. No toolkit here: the shell draws what these say. */

namespace Col {
    public enum IslandState {
        /* Nothing to show: only a thin strip at the top edge listens for the pointer. */
        HIDDEN,
        /* The closed capsule, with what is happening in it. */
        COLLAPSED,
        /* The pointer rests on it: the capsule swells a little to say it is there. */
        PEEK,
        /* Open, with its pages. */
        EXPANDED;

        public bool is_open () {
            return this == EXPANDED;
        }
    }

    /* How big the open island is. Standard matches the proportions of the Mac's open island. */
    public enum IslandSize {
        COMPACT,
        STANDARD,
        LARGE;

        public static IslandSize from_key (string? key) {
            switch (key) {
            case "compact": return COMPACT;
            case "large": return LARGE;
            default: return STANDARD;
            }
        }

        public unowned string to_key () {
            switch (this) {
            case COMPACT: return "compact";
            case LARGE: return "large";
            default: return "standard";
            }
        }

        public double open_width () {
            switch (this) {
            case COMPACT: return 440;
            case LARGE: return 540;
            default: return 480;
            }
        }

        public double open_height () {
            switch (this) {
            case COMPACT: return 184;
            case LARGE: return 224;
            default: return 200;
            }
        }
    }

    /* A rounded rectangle on the centre line of the screen: its centre, its top, its size and the radius of its corners. */
    public struct Frame {
        public double cx;
        public double y;
        public double width;
        public double height;
        public double radius;

        public Frame (double cx, double y, double width, double height, double radius) {
            this.cx = cx;
            this.y = y;
            this.width = width;
            this.height = height;
            this.radius = radius;
        }

        public double left () {
            return cx - width / 2;
        }

        public double right () {
            return cx + width / 2;
        }

        public double bottom () {
            return y + height;
        }

        /* The radius actually drawn: never more than half the shorter side, so a capsule stays a capsule. */
        public double effective_radius () {
            return double.max (0, double.min (radius, double.min (height / 2, width / 2)));
        }

        public bool contains (double px, double py) {
            return px >= left () && px <= right () && py >= y && py <= bottom ();
        }
    }

    /* Receives an outline, segment by segment: a Cairo context in the shell, a recorder in the tests. */
    public interface PathSink : Object {
        public abstract void move_to (double x, double y);
        public abstract void line_to (double x, double y);
        public abstract void curve_to (double x1, double y1, double x2, double y2, double x3, double y3);
        public abstract void close_path ();
    }

    namespace Geometry {
        /* The closed island: a capsule as tall as the Mac's floating one. */
        public const double PILL_HEIGHT = 34;
        /* What the capsule gains when the pointer rests on it. */
        public const double PEEK_TALLER = 4;
        public const double PEEK_WIDER = 16;
        /* The capsule at rest, with nothing in it, when it is set to stay visible. */
        public const double REST_WIDTH = 120;
        /* Widest the closed island may grow, so a long title never covers half the screen. */
        public const double MAX_COMPACT_WIDTH = 440;
        /* What the capsule shrinks to as it leaves. */
        public const double HIDDEN_WIDTH = 64;
        public const double HIDDEN_HEIGHT = 14;
        public const double OPEN_RADIUS = 32;
        /* Distance between the top of the screen (or of the panel) and the island: it floats, detached. */
        public const double GAP = 6;
        /* Room for the shadow around the open island. */
        public const double SHADOW = 28;
        /* Room around the closed one. */
        public const double SMALL_MARGIN = 6;
        /* The input-only strip at the top edge that wakes a hidden island. */
        public const double STRIP_WIDTH = 240;
        public const double STRIP_HEIGHT = 3;

        /* A continuous corner spreads over more of each edge than a circular arc of the same radius. */
        public const double SMOOTHING = 1.28;
        /* Distance of the Bézier handles from the corner, as a share of the reach. A circle would sit at 0.448. */
        public const double HANDLE_RATIO = 0.36;

        /* The island's frame for a state, in a surface whose horizontal centre is `cx`. `compact_width` is the width the
         * closed island needs for what it shows. */
        public Frame frame (IslandState state, double cx, double compact_width, IslandSize size, double gap = GAP) {
            double width = compact_width.clamp (HIDDEN_WIDTH, MAX_COMPACT_WIDTH);
            switch (state) {
            case IslandState.HIDDEN:
                return Frame (cx, gap, HIDDEN_WIDTH, HIDDEN_HEIGHT, HIDDEN_HEIGHT / 2);
            case IslandState.COLLAPSED:
                return Frame (cx, gap, width, PILL_HEIGHT, PILL_HEIGHT / 2);
            case IslandState.PEEK:
                double tall = PILL_HEIGHT + PEEK_TALLER;
                return Frame (cx, gap, width + PEEK_WIDER, tall, tall / 2);
            default:
                return Frame (cx, gap, size.open_width (), size.open_height (), OPEN_RADIUS);
            }
        }

        /* The surface the island needs to draw a state, shadow included. Sizes are even, so the centre never falls
         * between two pixels. */
        public void envelope (IslandState state, IslandSize size, double gap, out int width, out int height) {
            double w, h;
            switch (state) {
            case IslandState.HIDDEN:
                w = STRIP_WIDTH;
                h = STRIP_HEIGHT;
                break;
            case IslandState.COLLAPSED:
            case IslandState.PEEK:
                w = MAX_COMPACT_WIDTH + PEEK_WIDER + SMALL_MARGIN * 2;
                h = gap + PILL_HEIGHT + PEEK_TALLER + SMALL_MARGIN;
                break;
            default:
                w = double.max (size.open_width (), MAX_COMPACT_WIDTH + PEEK_WIDER) + SHADOW * 2;
                h = gap + size.open_height () + SHADOW;
                break;
            }
            width = even ((int) Math.ceil (w));
            height = (int) Math.ceil (h);
        }

        public int even (int value) {
            return value % 2 == 0 ? value : value + 1;
        }

        /* The outline of a frame: a rounded rectangle whose corners ease into the straight edges (continuous
         * curvature), which reads softer than a circular arc of the same radius. Every outline is made of the same
         * segments, so one can be blended into another. */
        public void outline (Frame f, PathSink sink) {
            double left = f.left (), right = f.right (), top = f.y, bottom = f.bottom ();
            double radius = f.effective_radius ();
            double reach = double.min (radius * SMOOTHING, double.min (f.height / 2, f.width / 2));
            double handle = reach * HANDLE_RATIO;
            sink.move_to (left + reach, top);
            sink.line_to (right - reach, top);
            sink.curve_to (right - handle, top, right, top + handle, right, top + reach);
            sink.line_to (right, bottom - reach);
            sink.curve_to (right, bottom - handle, right - handle, bottom, right - reach, bottom);
            sink.line_to (left + reach, bottom);
            sink.curve_to (left + handle, bottom, left, bottom - handle, left, bottom - reach);
            sink.line_to (left, top + reach);
            sink.curve_to (left, top + handle, left + handle, top, left + reach, top);
            sink.close_path ();
        }
    }

    /* How a spring moves: SwiftUI's perceptual duration and bounce, turned into stiffness and damping. */
    public struct Motion {
        public double stiffness;
        public double damping;

        public Motion (double duration, double bounce) {
            double omega = 2 * Math.PI / duration;
            stiffness = omega * omega;
            damping = 2 * (1 - bounce) * omega;
        }

        /* Opening overshoots a little, like something with weight. */
        public static Motion opening () {
            return Motion (0.5, 0.22);
        }

        public static Motion peeking () {
            return Motion (0.35, 0.3);
        }

        /* Closing settles without a bounce, so the island tucks back in cleanly. */
        public static Motion closing () {
            return Motion (0.38, 0);
        }

        /* Fades and small changes of content. */
        public static Motion fading () {
            return Motion (0.25, 0);
        }
    }

    /* One value moved by a spring. Stepped only while it moves: at rest nothing ticks. */
    public class Spring {
        public double value;
        public double velocity;
        public double target;
        public Motion motion;

        public Spring (double value) {
            this.value = value;
            this.target = value;
            this.velocity = 0;
            this.motion = Motion.closing ();
        }

        public void animate_to (double target, Motion motion) {
            this.target = target;
            this.motion = motion;
        }

        public void jump_to (double target) {
            this.target = target;
            this.value = target;
            this.velocity = 0;
        }

        public bool is_settled () {
            return Math.fabs (value - target) < 0.01 && Math.fabs (velocity) < 0.05;
        }

        /* Advances by `dt` seconds. Returns true while the value still moves. Small sub-steps keep stiff springs stable
         * when a frame comes late. */
        public bool step (double dt) {
            if (is_settled ()) {
                value = target;
                velocity = 0;
                return false;
            }
            dt = dt.clamp (0, 0.1);
            int steps = int.max (1, (int) Math.ceil (dt / 0.004));
            double h = dt / steps;
            for (int i = 0; i < steps; i++) {
                double force = -motion.stiffness * (value - target) - motion.damping * velocity;
                velocity += force * h;
                value += velocity * h;
            }
            if (is_settled ()) {
                value = target;
                velocity = 0;
                return false;
            }
            return true;
        }
    }
}
