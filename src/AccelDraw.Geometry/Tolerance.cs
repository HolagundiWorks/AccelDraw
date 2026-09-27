namespace AccelDraw.Geometry
{
    /// <summary>
    /// Configurable comparison tolerances (spec section 18). Defaults match the spec's example;
    /// callers should not hard-code architectural tolerances on top of these.
    /// </summary>
    public class Tolerance
    {
        public double LinearTolerance { get; set; } = 0.001;
        public double AngularTolerance { get; set; } = 0.0001;

        public static Tolerance Default => new Tolerance();
    }
}
