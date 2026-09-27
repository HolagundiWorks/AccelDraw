using AccelDraw.Geometry;
using AccelDraw.Snapshot;

namespace AccelDraw.Core.Interfaces
{
    /// <summary>Time Machine snapshot lifecycle (spec section 27).</summary>
    public interface ISnapshotService
    {
        Snapshot CreateSnapshot(VectorDocument document);

        Snapshot LoadSnapshot(string snapshotId);

        void RestoreSnapshot(Snapshot snapshot);
    }
}
