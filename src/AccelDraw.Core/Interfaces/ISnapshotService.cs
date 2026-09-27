using AccelDraw.Geometry;
using AccelDraw.Snapshot;

namespace AccelDraw.Core.Interfaces
{
    /// <summary>Time Machine snapshot lifecycle (spec section 27).</summary>
    public interface ISnapshotService
    {
        LoadedSnapshot CreateSnapshot(VectorDocument document);

        LoadedSnapshot LoadSnapshot(string snapshotId);

        void RestoreSnapshot(LoadedSnapshot snapshot);
    }
}
