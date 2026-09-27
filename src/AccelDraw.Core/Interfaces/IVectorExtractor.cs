using System.Collections.Generic;
using AccelDraw.Geometry;
using Autodesk.AutoCAD.DatabaseServices;

namespace AccelDraw.Core.Interfaces
{
    /// <summary>Reads selected AutoCAD entities into a normalized <see cref="VectorDocument"/> (spec section 27).</summary>
    public interface IVectorExtractor
    {
        VectorDocument Extract(Database database, IEnumerable<ObjectId> objectIds);
    }
}
