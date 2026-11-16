namespace Col.Core;

/// <summary>
/// A spring described the way people feel it: how long it seems to take, and how much it bounces (0 settles without
/// overshooting, 0.3 overshoots a little, like something with weight). The same parameters as the Mac's springs.
/// </summary>
public readonly record struct Spring(double PerceptualDuration, double Bounce)
{
    /// <summary>Opening overshoots a little.</summary>
    public static readonly Spring Open = new(0.5, 0.22);
    /// <summary>Peeking swells with a small bounce.</summary>
    public static readonly Spring Peek = new(0.35, 0.3);
    /// <summary>Closing settles without a bounce, so the island tucks back cleanly.</summary>
    public static readonly Spring Close = new(0.38, 0);
    /// <summary>When Windows' animations are off: short, no bounce.</summary>
    public static readonly Spring Reduced = new(0.2, 0);

    public static Spring Toward(IslandState state, bool reduceMotion) => reduceMotion
        ? Reduced
        : state switch
        {
            IslandState.Expanded => Open,
            IslandState.Peek => Peek,
            _ => Close,
        };

    /// <summary>Natural angular frequency.</summary>
    public double Omega => 2 * Math.PI / Math.Max(PerceptualDuration, 0.01);

    /// <summary>Damping ratio: one minus the bounce, so a bounce of zero is critically damped.</summary>
    public double DampingRatio => Math.Clamp(1 - Bounce, 0.05, 1);

    /// <summary>
    /// Displacement from the target and velocity at time <paramref name="t"/>, for a spring that started
    /// <paramref name="x0"/> away from its target with velocity <paramref name="v0"/>.
    /// </summary>
    public (double X, double V) Evaluate(double x0, double v0, double t)
    {
        var w = Omega;
        var z = DampingRatio;
        if (z >= 1)
        {
            // Critically damped: x(t) = e^(-wt) (x0 + (v0 + w x0) t).
            var b = v0 + w * x0;
            var e = Math.Exp(-w * t);
            var x = e * (x0 + b * t);
            var v = e * (b - w * (x0 + b * t));
            return (x, v);
        }
        var wd = w * Math.Sqrt(1 - z * z);
        var decay = Math.Exp(-z * w * t);
        var a = x0;
        var c = (v0 + z * w * x0) / wd;
        var cos = Math.Cos(wd * t);
        var sin = Math.Sin(wd * t);
        var xu = decay * (a * cos + c * sin);
        var vu = decay * ((-a * wd + c * -z * w) * sin + (c * wd - z * w * a) * cos);
        return (xu, vu);
    }

    /// <summary>Time after which the spring stays within <paramref name="epsilon"/> of its target (as a fraction of
    /// the distance travelled), at most three seconds.</summary>
    public double SettlingTime(double epsilon = 0.001)
    {
        for (var t = 0.0; t < 3; t += 1.0 / 240)
        {
            if (IsSettled(1, 0, t, epsilon)) return t;
        }
        return 3;
    }

    /// <summary>Whether a motion that started <paramref name="x0"/> away with velocity <paramref name="v0"/> has
    /// settled at time <paramref name="t"/>: its envelope, not only its position, is within reach of the target.</summary>
    public bool IsSettled(double x0, double v0, double t, double epsilon = 0.001)
    {
        var scale = Math.Max(Math.Abs(x0), 1e-9);
        var w = Omega;
        var z = DampingRatio;
        double envelope;
        if (z >= 1)
        {
            var b = Math.Abs(v0 + w * x0);
            envelope = Math.Exp(-w * t) * (Math.Abs(x0) + b * t);
        }
        else
        {
            var wd = w * Math.Sqrt(1 - z * z);
            var c = Math.Abs((v0 + z * w * x0) / wd);
            envelope = Math.Exp(-z * w * t) * (Math.Abs(x0) + c);
        }
        return envelope / scale < epsilon;
    }
}

/// <summary>
/// One value moved by a spring, which can be sent somewhere else mid-way: the new motion starts from where the value
/// is, at the speed it has, so an island that closes while it opens turns around smoothly.
/// </summary>
public sealed class SpringValue
{
    private double _from;
    private double _velocity;
    private double _start;
    private Spring _spring;

    public double Target { get; private set; }
    public bool IsMoving { get; private set; }

    public SpringValue(double value)
    {
        Target = value;
        _from = value;
    }

    /// <summary>The value at a moment, in seconds on the host's clock.</summary>
    public double ValueAt(double now)
    {
        if (!IsMoving) return Target;
        var (x, _) = _spring.Evaluate(_from - Target, _velocity, Math.Max(0, now - _start));
        return Target + x;
    }

    public double VelocityAt(double now)
    {
        if (!IsMoving) return 0;
        return _spring.Evaluate(_from - Target, _velocity, Math.Max(0, now - _start)).V;
    }

    /// <summary>Sends the value toward a new target from where it is now.</summary>
    public void Animate(double target, Spring spring, double now)
    {
        var current = ValueAt(now);
        var velocity = VelocityAt(now);
        if (Math.Abs(target - current) < 1e-6 && Math.Abs(velocity) < 1e-3)
        {
            Snap(target);
            return;
        }
        _from = current;
        _velocity = velocity;
        _start = now;
        _spring = spring;
        Target = target;
        IsMoving = true;
    }

    public void Snap(double value)
    {
        Target = value;
        _from = value;
        _velocity = 0;
        IsMoving = false;
    }

    /// <summary>Stops the motion once it has settled; returns whether it still moves.</summary>
    public bool Step(double now)
    {
        if (!IsMoving) return false;
        var distance = _from - Target;
        // Settled when within a hundredth of a pixel, or a thousandth of the way, whichever is larger.
        var epsilon = Math.Max(0.001, 0.01 / Math.Max(Math.Abs(distance), 1e-9));
        if (_spring.IsSettled(distance, _velocity, now - _start, epsilon))
        {
            Snap(Target);
            return false;
        }
        return true;
    }
}
