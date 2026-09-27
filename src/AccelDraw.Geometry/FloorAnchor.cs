namespace AccelDraw.Geometry
{
    /// <summary>
    /// A named, persistent WCS reference point shared by every drawing in a project — e.g. one per
    /// building floor ("Ground Floor", "First Floor", ...). A snapshot can record which anchor it
    /// was saved relative to (<see cref="AccelDraw.Snapshot.SnapshotManifest.FloorAnchor"/>), so if
    /// the anchor is later redefined (the floor's plan moves), a restore can follow it instead of
    /// staying pinned to the anchor's old position.
    /// </summary>
    public class FloorAnchor
    {
        public string Name { get; set; }
        public Point3D Origin { get; set; }
    }
}
