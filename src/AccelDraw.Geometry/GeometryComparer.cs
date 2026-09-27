using System;
using System.Collections.Generic;
using System.Linq;

namespace AccelDraw.Geometry
{
    /// <summary>
    /// Deterministic, tolerance-based comparison between a stored snapshot and the current drawing
    /// (spec sections 17-18). Purely geometric — no architectural interpretation.
    /// </summary>
    public class GeometryComparer
    {
        private readonly Tolerance _tolerance;

        public GeometryComparer(Tolerance tolerance = null)
        {
            _tolerance = tolerance ?? Tolerance.Default;
        }

        public ComparisonResult Compare(VectorDocument previous, VectorDocument current)
        {
            var result = new ComparisonResult();
            var remainingCurrent = current.Entities.ToDictionary(e => e.SourceHandle, e => e);

            foreach (var prev in previous.Entities)
            {
                if (remainingCurrent.TryGetValue(prev.SourceHandle, out var match) && match.EntityType == prev.EntityType)
                {
                    remainingCurrent.Remove(prev.SourceHandle);
                    result.Comparisons.Add(new EntityComparison
                    {
                        Previous = prev,
                        Current = match,
                        ChangeType = Classify(prev, match)
                    });
                }
                else
                {
                    result.Comparisons.Add(new EntityComparison
                    {
                        Previous = prev,
                        Current = null,
                        ChangeType = ChangeType.Removed
                    });
                }
            }

            foreach (var added in remainingCurrent.Values)
            {
                result.Comparisons.Add(new EntityComparison
                {
                    Previous = null,
                    Current = added,
                    ChangeType = ChangeType.Added
                });
            }

            return result;
        }

        private ChangeType Classify(VectorEntity previous, VectorEntity current)
        {
            var (shapeSame, translation) = CompareShape(previous.Geometry, current.Geometry, previous.EntityType);
            bool propertiesSame = PropertiesEqual(previous.Properties, current.Properties);

            if (!shapeSame)
                return ChangeType.Modified;

            bool isTranslated = translation.HasValue && translation.Value.DistanceTo(new Point3D(0, 0, 0)) > _tolerance.LinearTolerance;

            if (!isTranslated && propertiesSame)
                return ChangeType.Unchanged;

            if (isTranslated)
                return ChangeType.Moved;

            // Shape and position identical, but a non-geometric property changed.
            return ChangeType.Modified;
        }

        /// <summary>
        /// Returns whether the entity's shape (size/angles/text/etc., ignoring a uniform translation)
        /// is the same within tolerance, and the translation vector if one consistent translation
        /// explains the position difference.
        /// </summary>
        private (bool shapeSame, Point3D? translation) CompareShape(EntityGeometry a, EntityGeometry b, EntityType type)
        {
            double lt = _tolerance.LinearTolerance;
            double at = _tolerance.AngularTolerance;

            switch (type)
            {
                case EntityType.Line:
                {
                    if (a.Start == null || a.End == null || b.Start == null || b.End == null)
                        return (false, null);

                    var dStart = Delta(a.Start.Value, b.Start.Value);
                    var dEnd = Delta(a.End.Value, b.End.Value);
                    double lenA = a.Start.Value.DistanceTo(a.End.Value);
                    double lenB = b.Start.Value.DistanceTo(b.End.Value);
                    bool sameLength = Math.Abs(lenA - lenB) <= lt;
                    bool consistentTranslation = dStart.DistanceTo(dEnd) <= lt;
                    return (sameLength && consistentTranslation, consistentTranslation ? dStart : (Point3D?)null);
                }

                case EntityType.Circle:
                {
                    if (a.Center == null || b.Center == null || !a.Radius.HasValue || !b.Radius.HasValue)
                        return (false, null);

                    bool sameRadius = Math.Abs(a.Radius.Value - b.Radius.Value) <= lt;
                    var d = Delta(a.Center.Value, b.Center.Value);
                    return (sameRadius, sameRadius ? d : (Point3D?)null);
                }

                case EntityType.Arc:
                {
                    if (a.Center == null || b.Center == null || !a.Radius.HasValue || !b.Radius.HasValue
                        || !a.StartAngle.HasValue || !b.StartAngle.HasValue || !a.EndAngle.HasValue || !b.EndAngle.HasValue)
                        return (false, null);

                    bool sameRadius = Math.Abs(a.Radius.Value - b.Radius.Value) <= lt;
                    bool sameAngles = Math.Abs(a.StartAngle.Value - b.StartAngle.Value) <= at
                                       && Math.Abs(a.EndAngle.Value - b.EndAngle.Value) <= at;
                    var d = Delta(a.Center.Value, b.Center.Value);
                    return (sameRadius && sameAngles, (sameRadius && sameAngles) ? d : (Point3D?)null);
                }

                case EntityType.LwPolyline:
                {
                    if (a.Vertices == null || b.Vertices == null || a.Vertices.Count != b.Vertices.Count)
                        return (false, null);
                    if (a.Vertices.Count == 0)
                        return (true, new Point3D(0, 0, 0));

                    var translation = Delta(a.Vertices[0], b.Vertices[0]);
                    bool consistent = true;
                    for (int i = 0; i < a.Vertices.Count; i++)
                    {
                        var d = Delta(a.Vertices[i], b.Vertices[i]);
                        if (d.DistanceTo(translation) > lt)
                        {
                            consistent = false;
                            break;
                        }
                    }

                    bool bulgesSame = BulgesEqual(a.Bulges, b.Bulges, at);
                    return (consistent && bulgesSame, (consistent && bulgesSame) ? translation : (Point3D?)null);
                }

                case EntityType.Text:
                case EntityType.MText:
                {
                    if (a.Position == null || b.Position == null)
                        return (false, null);

                    bool sameText = string.Equals(a.TextValue, b.TextValue, StringComparison.Ordinal);
                    bool sameHeight = Math.Abs((a.Height ?? 0) - (b.Height ?? 0)) <= lt;
                    bool sameRotation = Math.Abs((a.Rotation ?? 0) - (b.Rotation ?? 0)) <= at;
                    bool shapeSame = sameText && sameHeight && sameRotation;
                    var d = Delta(a.Position.Value, b.Position.Value);
                    return (shapeSame, shapeSame ? d : (Point3D?)null);
                }

                case EntityType.BlockReference:
                {
                    if (a.InsertionPoint == null || b.InsertionPoint == null)
                        return (false, null);

                    bool sameBlock = string.Equals(a.BlockName, b.BlockName, StringComparison.OrdinalIgnoreCase);
                    var scaleA = a.Scale ?? new Point3D(1, 1, 1);
                    var scaleB = b.Scale ?? new Point3D(1, 1, 1);
                    bool sameScale = scaleA.DistanceTo(scaleB) <= lt;
                    bool sameRotation = Math.Abs((a.Rotation ?? 0) - (b.Rotation ?? 0)) <= at;
                    bool shapeSame = sameBlock && sameScale && sameRotation;
                    var d = Delta(a.InsertionPoint.Value, b.InsertionPoint.Value);
                    return (shapeSame, shapeSame ? d : (Point3D?)null);
                }

                default:
                    return (false, null);
            }
        }

        private static bool BulgesEqual(List<double> a, List<double> b, double tolerance)
        {
            if (a == null || b == null)
                return a == b;
            if (a.Count != b.Count)
                return false;
            for (int i = 0; i < a.Count; i++)
            {
                if (Math.Abs(a[i] - b[i]) > tolerance)
                    return false;
            }
            return true;
        }

        private static bool PropertiesEqual(EntityProperties a, EntityProperties b)
        {
            if (a == null || b == null)
                return a == b;
            return string.Equals(a.Layer, b.Layer, StringComparison.Ordinal)
                   && a.Color == b.Color
                   && string.Equals(a.Linetype, b.Linetype, StringComparison.Ordinal)
                   && a.Lineweight == b.Lineweight;
        }

        private static Point3D Delta(Point3D from, Point3D to) => new Point3D(to.X - from.X, to.Y - from.Y, to.Z - from.Z);
    }
}
