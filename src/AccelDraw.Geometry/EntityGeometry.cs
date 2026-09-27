using System.Collections.Generic;

namespace AccelDraw.Geometry
{
    /// <summary>
    /// Normalized WCS geometry for one entity. Only the fields relevant to the entity's
    /// <see cref="EntityType"/> are populated; the rest stay null. Never rounded.
    /// </summary>
    public class EntityGeometry
    {
        // LINE
        public Point3D? Start { get; set; }
        public Point3D? End { get; set; }

        // CIRCLE / ARC
        public Point3D? Center { get; set; }
        public double? Radius { get; set; }
        public double? StartAngle { get; set; }
        public double? EndAngle { get; set; }
        public Point3D? Normal { get; set; }

        // LWPOLYLINE (vertices in WCS; bulge per vertex, 0 for a straight segment)
        public List<Point3D> Vertices { get; set; }
        public List<double> Bulges { get; set; }
        public bool IsClosed { get; set; }

        // TEXT / MTEXT
        public Point3D? Position { get; set; }
        public double? Height { get; set; }
        public double? Rotation { get; set; }
        public string TextValue { get; set; }

        // BLOCKREFERENCE
        public string BlockName { get; set; }
        public Point3D? InsertionPoint { get; set; }
        public Point3D? Scale { get; set; }
    }
}
