using System;
using System.Collections.Generic;
using System.IO;
using AccelDraw.Geometry;
using Xunit;

namespace AccelDraw.Snapshot.Tests
{
    public class SnapshotRoundTripTests : IDisposable
    {
        private readonly string _workDir;

        public SnapshotRoundTripTests()
        {
            _workDir = Path.Combine(Path.GetTempPath(), "aicad-snapshot-tests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_workDir);
        }

        public void Dispose()
        {
            if (Directory.Exists(_workDir))
                Directory.Delete(_workDir, recursive: true);
        }

        [Fact]
        public void WriteThenRead_PreservesManifestAndFullPrecisionGeometry()
        {
            const double preciseX = 1000.123456789012;
            const double preciseY = 84000.987654321098;

            var manifest = new SnapshotManifest
            {
                SnapshotId = "TM-000001",
                Name = "Ground Floor - Revision 01",
                CreatedAt = DateTimeOffset.Parse("2026-09-27T08:00:00+05:30"),
                Selection = new SnapshotManifest.SelectionInfo { EntityCount = 1, BasePoint = new[] { preciseX, preciseY, 0.0 } }
            };

            var document = new VectorDocument
            {
                Entities = new List<VectorEntity>
                {
                    new VectorEntity
                    {
                        Id = "entity-00001",
                        SnapshotEntityId = "TM-000001/entity-00001",
                        SourceHandle = "A7F2",
                        SourceObjectType = "AcDbLine",
                        EntityType = EntityType.Line,
                        Geometry = new EntityGeometry
                        {
                            Start = new Point3D(preciseX, preciseY, 0),
                            End = new Point3D(preciseX + 4000.0, preciseY, 0)
                        },
                        Properties = new EntityProperties { Layer = "A-WALL", Color = 256, Linetype = "ByLayer", Lineweight = -1 }
                    }
                }
            };

            string dummyDwgPath = Path.Combine(_workDir, "source.dwg");
            byte[] dummyDwgBytes = { 0x41, 0x43, 0x31, 0x30, 0x32, 0x34 }; // arbitrary bytes standing in for a real DWG
            File.WriteAllBytes(dummyDwgPath, dummyDwgBytes);

            var writer = new SnapshotWriter();
            string packagePath = writer.Write(_workDir, manifest, document, dummyDwgPath);

            Assert.True(File.Exists(packagePath));

            var reader = new SnapshotReader();
            var loaded = reader.Load(packagePath);

            Assert.Equal(manifest.SnapshotId, loaded.Manifest.SnapshotId);
            Assert.Equal(manifest.Name, loaded.Manifest.Name);
            Assert.Equal(1, loaded.Manifest.Selection.EntityCount);

            var loadedEntity = Assert.Single(loaded.Vectors.Entities);
            Assert.Equal(preciseX, loadedEntity.Geometry.Start.Value.X, precision: 12);
            Assert.Equal(preciseY, loadedEntity.Geometry.Start.Value.Y, precision: 12);
            Assert.Equal("A7F2", loadedEntity.SourceHandle);

            Assert.True(File.Exists(loaded.ExtractedDwgPath));
            Assert.Equal(dummyDwgBytes, File.ReadAllBytes(loaded.ExtractedDwgPath));

            File.Delete(loaded.ExtractedDwgPath);
        }

        [Fact]
        public void UnsupportedEntities_AreRecordedInManifest_NotInVectors()
        {
            var manifest = new SnapshotManifest { SnapshotId = "TM-000002", Name = "Mixed selection" };
            manifest.UnsupportedEntities.Add(new SnapshotManifest.UnsupportedEntity { Handle = "B100", ObjectType = "AcDbHatch" });

            var document = new VectorDocument();

            string dummyDwgPath = Path.Combine(_workDir, "source2.dwg");
            File.WriteAllBytes(dummyDwgPath, new byte[] { 0x00 });

            var writer = new SnapshotWriter();
            string packagePath = writer.Write(_workDir, manifest, document, dummyDwgPath);

            var reader = new SnapshotReader();
            var readManifest = reader.ReadManifest(packagePath);

            var unsupported = Assert.Single(readManifest.UnsupportedEntities);
            Assert.Equal("B100", unsupported.Handle);
            Assert.Equal("AcDbHatch", unsupported.ObjectType);
            Assert.Equal("unsupported", unsupported.Status);
        }
    }
}
