using System.Collections.Generic;

namespace AccelDraw.Geometry
{
    /// <summary>
    /// The normalized vector representation of a selection (spec section 5B / 8): a flat list of
    /// <see cref="VectorEntity"/> records, WCS-normalized, ready for storage, comparison, or future
    /// geometry-intelligence processing.
    /// </summary>
    public class VectorDocument
    {
        public List<VectorEntity> Entities { get; set; } = new List<VectorEntity>();

        public Point3D BasePoint { get; set; }
    }
}
