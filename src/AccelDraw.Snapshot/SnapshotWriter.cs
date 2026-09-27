using System;
using System.IO;
using System.IO.Compression;
using AccelDraw.Geometry;
using Newtonsoft.Json;

namespace AccelDraw.Snapshot
{
    /// <summary>
    /// Packages a manifest, normalized vectors, and an already-saved native DWG side-database
    /// into one .adw ZIP container (spec section 6-7). Building the DWG itself requires the
    /// AutoCAD API, so the caller (AccelDraw.Plugin) supplies its path.
    /// </summary>
    public class SnapshotWriter
    {
        public string Write(string outputDirectory, SnapshotManifest manifest, VectorDocument vectors, string sourceDwgPath)
        {
            if (!Directory.Exists(outputDirectory))
                Directory.CreateDirectory(outputDirectory);

            string packagePath = Path.Combine(outputDirectory, manifest.SnapshotId + ".adw");
            string tempDir = Path.Combine(Path.GetTempPath(), "acceldraw-write-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);

            try
            {
                string manifestPath = Path.Combine(tempDir, "manifest.json");
                File.WriteAllText(manifestPath, JsonConvert.SerializeObject(manifest, Formatting.Indented));

                string vectorsPath = Path.Combine(tempDir, manifest.Files.Vectors);
                File.WriteAllText(vectorsPath, JsonConvert.SerializeObject(vectors, Formatting.Indented));

                string dwgDestPath = Path.Combine(tempDir, manifest.Files.Dwg);
                File.Copy(sourceDwgPath, dwgDestPath, overwrite: true);

                if (File.Exists(packagePath))
                    File.Delete(packagePath);

                ZipFile.CreateFromDirectory(tempDir, packagePath, CompressionLevel.Optimal, includeBaseDirectory: false);
            }
            finally
            {
                Directory.Delete(tempDir, recursive: true);
            }

            return packagePath;
        }
    }
}
