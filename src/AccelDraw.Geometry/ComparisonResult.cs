using System.Collections.Generic;
using System.Linq;

namespace AccelDraw.Geometry
{
    public class ComparisonResult
    {
        public List<EntityComparison> Comparisons { get; set; } = new List<EntityComparison>();

        public int CountOf(ChangeType type) => Comparisons.Count(c => c.ChangeType == type);
    }
}
