using System.Collections.Generic;
using AccelDraw.Geometry;
using Xunit;

namespace AccelDraw.Geometry.Tests
{
    public class GeometryComparerTests
    {
        private static VectorEntity Line(string handle, double x1, double y1, double x2, double y2, string layer = "0")
        {
            return new VectorEntity
            {
                Id = "entity-00001",
                SourceHandle = handle,
                SourceObjectType = "AcDbLine",
                EntityType = EntityType.Line,
                Geometry = new EntityGeometry
                {
                    Start = new Point3D(x1, y1, 0),
                    End = new Point3D(x2, y2, 0)
                },
                Properties = new EntityProperties { Layer = layer, Color = 256, Linetype = "ByLayer", Lineweight = -1 }
            };
        }

        private static VectorDocument DocOf(params VectorEntity[] entities) => new VectorDocument { Entities = new List<VectorEntity>(entities) };

        [Fact]
        public void IdenticalLine_IsUnchanged()
        {
            var previous = DocOf(Line("A1", 0, 0, 5000, 0));
            var current = DocOf(Line("A1", 0, 0, 5000, 0));

            var result = new GeometryComparer().Compare(previous, current);

            Assert.Equal(ChangeType.Unchanged, Assert.Single(result.Comparisons).ChangeType);
        }

        [Fact]
        public void LengthenedLine_IsModified()
        {
            var previous = DocOf(Line("A1", 0, 0, 5000, 0));
            var current = DocOf(Line("A1", 0, 0, 5500, 0));

            var result = new GeometryComparer().Compare(previous, current);

            Assert.Equal(ChangeType.Modified, Assert.Single(result.Comparisons).ChangeType);
        }

        [Fact]
        public void TranslatedLine_IsMoved()
        {
            var previous = DocOf(Line("A1", 0, 0, 5000, 0));
            var current = DocOf(Line("A1", 500, 0, 5500, 0));

            var result = new GeometryComparer().Compare(previous, current);

            Assert.Equal(ChangeType.Moved, Assert.Single(result.Comparisons).ChangeType);
        }

        [Fact]
        public void EntityMissingFromCurrent_IsRemoved()
        {
            var previous = DocOf(Line("A1", 0, 0, 5000, 0));
            var current = DocOf();

            var result = new GeometryComparer().Compare(previous, current);

            Assert.Equal(ChangeType.Removed, Assert.Single(result.Comparisons).ChangeType);
        }

        [Fact]
        public void EntityOnlyInCurrent_IsAdded()
        {
            var previous = DocOf();
            var current = DocOf(Line("A1", 0, 0, 5000, 0));

            var result = new GeometryComparer().Compare(previous, current);

            Assert.Equal(ChangeType.Added, Assert.Single(result.Comparisons).ChangeType);
        }

        [Fact]
        public void SameGeometryDifferentLayer_IsModified()
        {
            var previous = DocOf(Line("A1", 0, 0, 5000, 0, layer: "A-WALL"));
            var current = DocOf(Line("A1", 0, 0, 5000, 0, layer: "A-DOOR"));

            var result = new GeometryComparer().Compare(previous, current);

            Assert.Equal(ChangeType.Modified, Assert.Single(result.Comparisons).ChangeType);
        }

        [Fact]
        public void MixOfChanges_ClassifiesEachIndependently()
        {
            var previous = DocOf(
                Line("UNCHANGED", 0, 0, 100, 0),
                Line("MOVED", 0, 0, 100, 0),
                Line("REMOVED", 0, 0, 100, 0));

            var current = DocOf(
                Line("UNCHANGED", 0, 0, 100, 0),
                Line("MOVED", 10, 10, 110, 10),
                Line("ADDED", 200, 200, 300, 200));

            var result = new GeometryComparer().Compare(previous, current);

            Assert.Equal(1, result.CountOf(ChangeType.Unchanged));
            Assert.Equal(1, result.CountOf(ChangeType.Moved));
            Assert.Equal(1, result.CountOf(ChangeType.Removed));
            Assert.Equal(1, result.CountOf(ChangeType.Added));
        }
    }
}
