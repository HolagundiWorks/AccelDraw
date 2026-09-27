using System.Text;
using AccelDraw.Bridge;
using AccelDraw.Geometry;
using Newtonsoft.Json;

namespace AccelDraw.ShilpiDb
{
    /// <summary>
    /// Pushes/pulls a <see cref="VectorDocument"/>'s entities to/from a running shilpid, one
    /// ShilpiDB record per entity (bbox + JSON payload). This is the "server client" integration
    /// path the ShilpiDB README describes for AADT, applied to AccelDraw's own entity model instead
    /// of AADT's — the two hosts share the storage engine, not an entity schema.
    /// </summary>
    public class ShilpiSnapshotSync
    {
        private readonly ShilpiDbClient _client;

        public ShilpiSnapshotSync(ShilpiDbClient client)
        {
            _client = client;
        }

        /// <summary>
        /// Pushes every entity as its own record, plus — if <paramref name="tileExtent"/> is given —
        /// one extra "tile" record at <c>{snapshotId}/tile</c> whose box is the snapshot's
        /// manually-defined territory (see SnapshotManifest.Extent), not the union of its entities'
        /// boxes. That's what lets a spatial query answer "which snapshot covers this point?" even
        /// for a mostly-empty tile, or a tile whose declared boundary is bigger than what's drawn in it.
        /// </summary>
        public void Push(string snapshotId, ShilpiBbox? tileExtent, VectorDocument document)
        {
            foreach (var entity in document.Entities)
            {
                if (entity.IsUnsupported)
                    continue;

                ulong id = EntityIds.ToRecordId(entity.SnapshotEntityId);
                var bbox = EntityBbox.Compute(entity);
                byte[] payload = Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(entity));

                _client.Put(id, bbox, payload);
            }

            if (tileExtent.HasValue)
            {
                ulong tileId = EntityIds.ToRecordId(snapshotId + "/tile");
                byte[] tilePayload = Encoding.UTF8.GetBytes(
                    JsonConvert.SerializeObject(new { kind = "tile", snapshotId }));
                _client.Put(tileId, tileExtent.Value, tilePayload);
            }

            _client.Save();
        }

        public bool TryPull(string snapshotEntityId, out VectorEntity entity)
        {
            ulong id = EntityIds.ToRecordId(snapshotEntityId);
            if (!_client.TryGet(id, out _, out var payload))
            {
                entity = null;
                return false;
            }

            entity = JsonConvert.DeserializeObject<VectorEntity>(Encoding.UTF8.GetString(payload));
            return true;
        }

        public VectorDocument QueryRegion(ShilpiBbox region)
        {
            var document = new VectorDocument();
            foreach (var id in _client.QueryBbox(region))
            {
                if (_client.TryGet(id, out _, out var payload))
                    document.Entities.Add(JsonConvert.DeserializeObject<VectorEntity>(Encoding.UTF8.GetString(payload)));
            }
            return document;
        }
    }
}
