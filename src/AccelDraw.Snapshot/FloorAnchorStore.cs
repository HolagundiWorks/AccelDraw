using System.Collections.Generic;
using System.IO;
using System.Linq;
using AccelDraw.Geometry;
using Newtonsoft.Json;

namespace AccelDraw.Snapshot
{
    /// <summary>Reads/writes the project's shared <c>floor-anchors.json</c> (a flat list of <see cref="FloorAnchor"/>).</summary>
    public class FloorAnchorStore
    {
        private readonly string _path;

        public FloorAnchorStore(string path)
        {
            _path = path;
        }

        public List<FloorAnchor> List()
        {
            if (!File.Exists(_path))
                return new List<FloorAnchor>();

            return JsonConvert.DeserializeObject<List<FloorAnchor>>(File.ReadAllText(_path)) ?? new List<FloorAnchor>();
        }

        public FloorAnchor Get(string name) =>
            List().FirstOrDefault(a => string.Equals(a.Name, name, System.StringComparison.OrdinalIgnoreCase));

        /// <summary>Adds a new anchor or updates an existing one with the same name.</summary>
        public void Set(FloorAnchor anchor)
        {
            var anchors = List();
            anchors.RemoveAll(a => string.Equals(a.Name, anchor.Name, System.StringComparison.OrdinalIgnoreCase));
            anchors.Add(anchor);

            string dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                Directory.CreateDirectory(dir);

            File.WriteAllText(_path, JsonConvert.SerializeObject(anchors, Formatting.Indented));
        }
    }
}
