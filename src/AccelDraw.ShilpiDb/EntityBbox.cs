using System;
using System.Collections.Generic;
using AccelDraw.Bridge;
using AccelDraw.Geometry;

namespace AccelDraw.ShilpiDb
{
    /// <summary>Computes the WCS bounding box ShilpiDB's spatial index needs for a <see cref="VectorEntity"/>.</summary>
    public static class EntityBbox
    {
        public static ShilpiBbox Compute(VectorEntity entity)
        {
            var g = entity.Geometry;
            var points = new List<Point3D>();

            switch (entity.EntityType)
            {
                case EntityType.Line:
                    if (g.Start.HasValue) points.Add(g.Start.Value);
                    if (g.End.HasValue) points.Add(g.End.Value);
                    break;

                case EntityType.Circle:
                case EntityType.Arc:
                    if (g.Center.HasValue && g.Radius.HasValue)
                    {
                        var c = g.Center.Value;
                        double r = g.Radius.Value;
                        points.Add(new Point3D(c.X - r, c.Y - r, c.Z));
                        points.Add(new Point3D(c.X + r, c.Y + r, c.Z));
                    }
                    break;

                case EntityType.LwPolyline:
                    if (g.Vertices != null)
                        points.AddRange(g.Vertices);
                    break;

                case EntityType.Text:
                case EntityType.MText:
                    if (g.Position.HasValue)
                    {
                        var p = g.Position.Value;
                        double h = g.Height ?? 0;
                        points.Add(p);
                        points.Add(new Point3D(p.X, p.Y + h, p.Z));
                    }
                    break;

                case EntityType.BlockReference:
                    if (g.InsertionPoint.HasValue)
                        points.Add(g.InsertionPoint.Value);
                    break;
            }

            if (points.Count == 0)
                return ShilpiBbox.FromCorners(0, 0, 0, 0);

            double minX = double.MaxValue, minY = double.MaxValue, maxX = double.MinValue, maxY = double.MinValue;
            foreach (var p in points)
            {
                minX = Math.Min(minX, p.X);
                minY = Math.Min(minY, p.Y);
                maxX = Math.Max(maxX, p.X);
                maxY = Math.Max(maxY, p.Y);
            }

            return ShilpiBbox.FromCorners(minX, minY, maxX, maxY);
        }
    }
}
