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

        public void Push(VectorDocument document)
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
