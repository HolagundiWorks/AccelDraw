using System;
using System.IO;
using System.Security.Cryptography;
using Autodesk.AutoCAD.ApplicationServices;

namespace AccelDraw.Plugin.AutoCAD
{
    /// <summary>Resolves per-drawing paths and identity used by the Time Machine commands.</summary>
    public static class DrawingContext
    {
        private const string SnapshotsFolderName = "snapshots";

        /// <summary>
        /// Snapshots live in a "snapshots" folder next to the DWG. If the drawing has never been
        /// saved, they fall back to a per-user AccelDraw folder so ACCELDRAW_SAVE always works.
        /// </summary>
        public static string SnapshotsDirectory(Document doc)
        {
            string dwgPath = doc.Name;
            if (!string.IsNullOrEmpty(dwgPath) && File.Exists(dwgPath))
            {
                string dir = Path.GetDirectoryName(dwgPath);
                return Path.Combine(dir, SnapshotsFolderName);
            }

            string fallback = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "AccelDraw", "UnsavedDrawings", SnapshotsFolderName);
            return fallback;
        }

        public static string DrawingName(Document doc)
        {
            string dwgPath = doc.Name;
            return string.IsNullOrEmpty(dwgPath) ? "(unsaved)" : Path.GetFileName(dwgPath);
        }

        /// <summary>SHA-256 of the saved DWG file, or a placeholder when the drawing has unsaved changes on disk.</summary>
        public static string DrawingFingerprint(Document doc)
        {
            string dwgPath = doc.Name;
            if (string.IsNullOrEmpty(dwgPath) || !File.Exists(dwgPath))
                return "UNSAVED";

            using (var sha256 = SHA256.Create())
            using (var stream = File.OpenRead(dwgPath))
            {
                byte[] hash = sha256.ComputeHash(stream);
                return BitConverter.ToString(hash).Replace("-", "");
            }
        }
    }
}
