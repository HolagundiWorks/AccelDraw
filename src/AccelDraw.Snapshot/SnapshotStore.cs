using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace AccelDraw.Snapshot
{
    /// <summary>
    /// Minimal filesystem-backed snapshot index for this milestone (spec section 22's "canonical
    /// geometric store", scoped down): snapshots are addressed by folder + "TM-NNNNNN.adw" file
    /// name. A SQLite-backed MetadataStore can replace the scan-based listing later without
    /// changing this type's public surface.
    /// </summary>
    public class SnapshotStore
    {
        private readonly string _directory;
        private readonly SnapshotReader _reader = new SnapshotReader();

        public SnapshotStore(string directory)
        {
            _directory = directory;
            if (!Directory.Exists(_directory))
                Directory.CreateDirectory(_directory);
        }

        public string Directory => _directory;

        public string GenerateNextSnapshotId()
        {
            int max = System.IO.Directory.EnumerateFiles(_directory, "TM-*.adw")
                .Select(Path.GetFileNameWithoutExtension)
                .Select(name =>
                {
                    var parts = name.Split('-');
                    return parts.Length == 2 && int.TryParse(parts[1], out var n) ? n : 0;
                })
                .DefaultIfEmpty(0)
                .Max();

            return $"TM-{max + 1:D6}";
        }

        public string PackagePathFor(string snapshotId) => Path.Combine(_directory, snapshotId + ".adw");

        public IEnumerable<SnapshotManifest> ListManifests()
        {
            foreach (var path in System.IO.Directory.EnumerateFiles(_directory, "TM-*.adw").OrderBy(p => p))
            {
                yield return _reader.ReadManifest(path);
            }
        }

        public bool Exists(string snapshotId) => File.Exists(PackagePathFor(snapshotId));
    }
}
