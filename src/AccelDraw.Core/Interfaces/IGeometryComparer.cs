using AccelDraw.Geometry;

namespace AccelDraw.Core.Interfaces
{
    /// <summary>Deterministic geometric comparison between two vector documents (spec section 27).</summary>
    public interface IGeometryComparer
    {
        ComparisonResult Compare(VectorDocument previous, VectorDocument current);
    }
}
