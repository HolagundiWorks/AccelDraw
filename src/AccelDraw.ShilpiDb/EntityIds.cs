using System.Text;

namespace AccelDraw.ShilpiDb
{
    /// <summary>
    /// Maps a <c>VectorEntity.SnapshotEntityId</c> (e.g. "TM-000001/entity-00042") to the u64 id
    /// ShilpiDB records use. FNV-1a keeps this dependency-free, matching ShilpiDB's own std-only
    /// policy, but it is a hash, not a content-addressed id — a real collision is astronomically
    /// unlikely for one drawing's entity count, but this is a known simplification. AADT's
    /// blake3-based Merkle object ids (ADR-0021) are the ecosystem's answer to this properly; see
    /// docs/ROADMAP.md.
    /// </summary>
    public static class EntityIds
    {
        public static ulong ToRecordId(string snapshotEntityId)
        {
            const ulong fnvOffsetBasis = 14695981039346656037UL;
            const ulong fnvPrime = 1099511628211UL;

            ulong hash = fnvOffsetBasis;
            foreach (byte b in Encoding.UTF8.GetBytes(snapshotEntityId))
            {
                hash ^= b;
                hash *= fnvPrime;
            }
            return hash;
        }
    }
}
