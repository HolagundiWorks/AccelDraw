namespace AccelDraw.Geometry
{
    /// <summary>Insertion transform captured for entities that carry one (mainly BLOCKREFERENCE).</summary>
    public class Transform
    {
        public double Rotation { get; set; }
        public Point3D Scale { get; set; } = new Point3D(1, 1, 1);
        public Point3D Normal { get; set; } = new Point3D(0, 0, 1);
    }
}
