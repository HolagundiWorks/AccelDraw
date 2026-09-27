using System;
using System.IO;
using System.IO.Compression;
using AccelDraw.Geometry;
using Newtonsoft.Json;

namespace AccelDraw.Snapshot
{
    /// <summary>Reads a .adw package back into a <see cref="Snapshot"/> (spec section 6-7).</summary>
    public class SnapshotReader
    {
        public SnapshotManifest ReadManifest(string packagePath)
        {
            using (var archive = ZipFile.OpenRead(packagePath))
            {
                var entry = archive.GetEntry("manifest.json")
                    ?? throw new InvalidDataException($"'{packagePath}' has no manifest.json.");
                using (var stream = entry.Open())
                using (var reader = new StreamReader(stream))
                {
                    return JsonConvert.DeserializeObject<SnapshotManifest>(reader.ReadToEnd());
                }
            }
        }

        /// <summary>
        /// Loads the full snapshot: manifest, normalized vectors, and extracts snapshot.dwg to a
        /// fresh temp file (the caller is responsible for opening/disposing it via the AutoCAD API).
        /// </summary>
        public Snapshot Load(string packagePath)
        {
            var manifest = ReadManifest(packagePath);
            VectorDocument vectors;
            string extractedDwgPath = Path.Combine(Path.GetTempPath(), "acceldraw-read-" + Guid.NewGuid().ToString("N") + ".dwg");

            using (var archive = ZipFile.OpenRead(packagePath))
            {
                var vectorsEntry = archive.GetEntry(manifest.Files.Vectors)
                    ?? throw new InvalidDataException($"'{packagePath}' has no {manifest.Files.Vectors}.");
                using (var stream = vectorsEntry.Open())
                using (var reader = new StreamReader(stream))
                {
                    vectors = JsonConvert.DeserializeObject<VectorDocument>(reader.ReadToEnd());
                }

                var dwgEntry = archive.GetEntry(manifest.Files.Dwg)
                    ?? throw new InvalidDataException($"'{packagePath}' has no {manifest.Files.Dwg}.");
                dwgEntry.ExtractToFile(extractedDwgPath, overwrite: true);
            }

            return new Snapshot
            {
                Manifest = manifest,
                Vectors = vectors,
                ExtractedDwgPath = extractedDwgPath,
                PackagePath = packagePath
            };
        }
    }
}
