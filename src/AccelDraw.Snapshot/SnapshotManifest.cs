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
    }
}
