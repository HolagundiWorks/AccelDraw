namespace AccelDraw.Geometry
{
    /// <summary>
    /// Normalized, machine-readable record of one selected AutoCAD entity (spec section 8).
    /// Identity rules (spec section 11): AutoCAD ObjectIds are transient and must never be relied
    /// on across sessions. The durable identity is <see cref="SnapshotEntityId"/>.
    /// </summary>
    public class VectorEntity
    {
        /// <summary>Snapshot-scoped stable id, e.g. "TM-000001/entity-00042". Empty until assigned a snapshot.</summary>
        public string SnapshotEntityId { get; set; }

        /// <summary>Sequential id within one extraction, e.g. "entity-00001".</summary>
        public string Id { get; set; }

        public string SourceHandle { get; set; }
        public string SourceObjectType { get; set; }

        public EntityType EntityType { get; set; }
        public EntityGeometry Geometry { get; set; }
        public EntityProperties Properties { get; set; }
        public Transform Transform { get; set; }

        /// <summary>True when the source object type is not one of the entities this milestone supports.</summary>
        public bool IsUnsupported => EntityType == EntityType.Unsupported;
    }
}
