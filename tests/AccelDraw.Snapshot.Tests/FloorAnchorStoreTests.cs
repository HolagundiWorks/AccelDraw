using System;
using System.IO;
using AccelDraw.Geometry;
using Xunit;

namespace AccelDraw.Snapshot.Tests
{
    public class FloorAnchorStoreTests : IDisposable
    {
        private readonly string _path;

        public FloorAnchorStoreTests()
        {
            _path = Path.Combine(Path.GetTempPath(), "acceldraw-anchor-tests-" + Guid.NewGuid().ToString("N"), "floor-anchors.json");
        }

        public void Dispose()
        {
            string dir = Path.GetDirectoryName(_path);
            if (dir != null && Directory.Exists(dir))
                Directory.Delete(dir, recursive: true);
        }

        [Fact]
        public void SetThenList_RoundTripsAnchor()
        {
            var store = new FloorAnchorStore(_path);
            store.Set(new FloorAnchor { Name = "Ground Floor", Origin = new Point3D(100.5, 200.25, 0) });

            var anchors = store.List();
            var anchor = Assert.Single(anchors);
            Assert.Equal("Ground Floor", anchor.Name);
            Assert.Equal(100.5, anchor.Origin.X);
            Assert.Equal(200.25, anchor.Origin.Y);
        }

        [Fact]
        public void Set_WithSameName_ReplacesExistingAnchor()
        {
            var store = new FloorAnchorStore(_path);
            store.Set(new FloorAnchor { Name = "First Floor", Origin = new Point3D(0, 0, 0) });
            store.Set(new FloorAnchor { Name = "First Floor", Origin = new Point3D(10, 10, 3000) });

            var anchors = store.List();
            var anchor = Assert.Single(anchors);
            Assert.Equal(10, anchor.Origin.X);
            Assert.Equal(3000, anchor.Origin.Z);
        }

        [Fact]
        public void Get_IsCaseInsensitiveByName()
        {
            var store = new FloorAnchorStore(_path);
            store.Set(new FloorAnchor { Name = "Ground Floor", Origin = new Point3D(1, 2, 3) });

            Assert.NotNull(store.Get("ground floor"));
            Assert.Null(store.Get("Second Floor"));
        }

        [Fact]
        public void List_OnMissingFile_ReturnsEmpty()
        {
            var store = new FloorAnchorStore(_path);
            Assert.Empty(store.List());
        }
    }
}
