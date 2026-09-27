namespace AccelDraw.Geometry
{
    /// <summary>One entity's classification result from a Compare pass.</summary>
    public class EntityComparison
    {
        public ChangeType ChangeType { get; set; }

        /// <summary>The previous (snapshot) entity, or null when <see cref="ChangeType"/> is Added.</summary>
        public VectorEntity Previous { get; set; }

        /// <summary>The current (drawing) entity, or null when <see cref="ChangeType"/> is Removed.</summary>
        public VectorEntity Current { get; set; }
    }
}
