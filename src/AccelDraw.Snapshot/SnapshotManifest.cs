using System;
using System.Collections.Generic;
using Newtonsoft.Json;

namespace AccelDraw.Snapshot
{
    /// <summary>Mirrors the manifest.json structure from spec section 7.</summary>
    public class SnapshotManifest
    {
        [JsonProperty("format")]
        public string Format { get; set; } = "AccelDraw";

        [JsonProperty("format_version")]
        public string FormatVersion { get; set; } = "1.0";

        [JsonProperty("snapshot_id")]
        public string SnapshotId { get; set; }

        [JsonProperty("name")]
        public string Name { get; set; }

        [JsonProperty("drawing")]
        public DrawingInfo Drawing { get; set; } = new DrawingInfo();

        [JsonProperty("created_at")]
        public DateTimeOffset CreatedAt { get; set; }

        [JsonProperty("autocad")]
        public AutoCadInfo AutoCad { get; set; } = new AutoCadInfo();

        [JsonProperty("coordinate_system")]
        public CoordinateSystemInfo CoordinateSystem { get; set; } = new CoordinateSystemInfo();

        [JsonProperty("selection")]
        public SelectionInfo Selection { get; set; } = new SelectionInfo();

        [JsonProperty("files")]
        public FilesInfo Files { get; set; } = new FilesInfo();

        /// <summary>Entities that were selected but are not supported by this milestone (spec section 9).</summary>
        [JsonProperty("unsupported_entities")]
        public List<UnsupportedEntity> UnsupportedEntities { get; set; } = new List<UnsupportedEntity>();

        /// <summary>Which project floor anchor (if any) this snapshot's base point was recorded relative to.</summary>
        [JsonProperty("floor_anchor")]
        public FloorAnchorRef FloorAnchor { get; set; }

        /// <summary>
        /// The manually-defined WCS rectangle this snapshot's "territory" covers — deliberately
        /// independent of the union of its entities' own boxes, so a tile's boundary stays fixed
        /// even if what's drawn inside it changes. This is what gets pushed to ShilpiDB as the
        /// tile's own record (see AccelDraw.ShilpiDb.ShilpiSnapshotSync), letting a spatial query
        /// find "which snapshot covers this point" independent of individual entities.
        /// </summary>
        [JsonProperty("extent")]
        public ExtentInfo Extent { get; set; }

        public class DrawingInfo
        {
            [JsonProperty("name")]
            public string Name { get; set; }

            [JsonProperty("fingerprint")]
            public string Fingerprint { get; set; }
        }

        public class AutoCadInfo
        {
            [JsonProperty("version")]
            public string Version { get; set; }
        }

        public class CoordinateSystemInfo
        {
            [JsonProperty("system")]
            public string System { get; set; } = "WCS";

            [JsonProperty("ucs_name")]
            public string UcsName { get; set; } = "World";
        }

        public class SelectionInfo
        {
            [JsonProperty("entity_count")]
            public int EntityCount { get; set; }

            [JsonProperty("base_point")]
            public double[] BasePoint { get; set; } = new double[3];
        }

        public class FilesInfo
        {
            [JsonProperty("dwg")]
            public string Dwg { get; set; } = "snapshot.dwg";

            [JsonProperty("vectors")]
            public string Vectors { get; set; } = "vectors.json";
        }

        public class UnsupportedEntity
        {
            [JsonProperty("handle")]
            public string Handle { get; set; }

            [JsonProperty("object_type")]
            public string ObjectType { get; set; }

            [JsonProperty("status")]
            public string Status { get; set; } = "unsupported";
        }

        /// <summary>
        /// The named anchor a snapshot's base point was recorded relative to, plus that anchor's
        /// WCS origin *at save time* — so a later restore can detect whether the anchor moved since
        /// (compare <see cref="OriginAtSave"/> to the project's current anchor of the same name) and
        /// shift the restored geometry to follow it.
        /// </summary>
        public class FloorAnchorRef
        {
            [JsonProperty("name")]
            public string Name { get; set; }

            [JsonProperty("origin_at_save")]
            public double[] OriginAtSave { get; set; }
        }

        public class ExtentInfo
        {
            [JsonProperty("min")]
            public double[] Min { get; set; }

            [JsonProperty("max")]
            public double[] Max { get; set; }
        }
    }
}
