namespace AccelDraw.Geometry
{
    /// <summary>
    /// Normalized entity type recognized by this milestone. Anything else is captured as
    /// <see cref="Unsupported"/> and recorded in the manifest rather than crashing the snapshot process.
    /// </summary>
    public enum EntityType
    {
        Unsupported = 0,
        Line,
        LwPolyline,
        Circle,
        Arc,
        Text,
        MText,
        BlockReference
    }
}
