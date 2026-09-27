using AccelDraw.Geometry;

namespace AccelDraw.Snapshot
{
    /// <summary>
    /// A loaded snapshot: manifest + normalized vectors + a filesystem path to the extracted
    /// native snapshot.dwg (spec section 5). The dwg is only extracted to disk on demand by
    /// <see cref="SnapshotReader"/> — AccelDraw.Snapshot never opens or interprets the DWG itself,
    /// since it has no AutoCAD API reference.
    /// </summary>
    public class Snapshot
    {
        public SnapshotManifest Manifest { get; set; }
        public VectorDocument Vectors { get; set; }

        /// <summary>Path to the extracted snapshot.dwg on disk, populated by SnapshotReader.Load().</summary>
        public string ExtractedDwgPath { get; set; }

        /// <summary>Path to the source .adw package this snapshot was loaded from.</summary>
        public string PackagePath { get; set; }
    }
}
