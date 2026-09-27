namespace AccelDraw.Bridge
{
    /// <summary>An axis-aligned WCS bounding box, matching shilpidb's <c>Bbox</c> at the FFI boundary.</summary>
    public struct ShilpiBbox
    {
        public double MinX { get; }
        public double MinY { get; }
        public double MaxX { get; }
        public double MaxY { get; }

        public ShilpiBbox(double minX, double minY, double maxX, double maxY)
        {
            MinX = minX;
            MinY = minY;
            MaxX = maxX;
            MaxY = maxY;
        }

        public static ShilpiBbox FromCorners(double x0, double y0, double x1, double y1) =>
            new ShilpiBbox(System.Math.Min(x0, x1), System.Math.Min(y0, y1), System.Math.Max(x0, x1), System.Math.Max(y0, y1));
    }
}
