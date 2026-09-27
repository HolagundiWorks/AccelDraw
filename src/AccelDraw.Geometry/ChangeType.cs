namespace AccelDraw.Geometry
{
    /// <summary>Deterministic geometric classification (spec section 17). No architectural interpretation.</summary>
    public enum ChangeType
    {
        Unchanged,
        Added,
        Removed,
        Modified,
        Moved
    }
}
