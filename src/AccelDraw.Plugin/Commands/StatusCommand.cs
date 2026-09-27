using System.IO;
using System.Linq;
using AccelDraw.Bridge;
using AccelDraw.Plugin.AutoCAD;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Runtime;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>
    /// ACCELDRAW_STATUS: one-shot usage/health overview — local snapshot count and disk usage,
    /// floor anchors defined for this project, and whether ShilpiDB sync is configured/reachable.
    /// </summary>
    public class StatusCommand
    {
        [CommandMethod("ACCELDRAW_STATUS")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var ed = doc.Editor;

            var snapshotsDir = DrawingContext.SnapshotsDirectory(doc);
            var store = new SnapshotStore(snapshotsDir);
            var manifests = store.ListManifests().ToList();
            long totalBytes = Directory.Exists(snapshotsDir)
                ? Directory.EnumerateFiles(snapshotsDir, "*.adw").Sum(p => new FileInfo(p).Length)
                : 0;

            ed.WriteMessage("\nACCELDRAW STATUS\n");
            ed.WriteMessage($"\nDrawing: {DrawingContext.DrawingName(doc)}\n");
            ed.WriteMessage($"Snapshots: {manifests.Count} ({totalBytes / 1024.0:F1} KB total) in {snapshotsDir}\n");

            int totalEntities = manifests.Sum(m => m.Selection.EntityCount);
            ed.WriteMessage($"Entities across all snapshots: {totalEntities}\n");

            var anchorStore = new FloorAnchorStore(DrawingContext.ProjectAnchorsPath(doc));
            var anchors = anchorStore.List();
            ed.WriteMessage($"Floor anchors defined: {anchors.Count}{(anchors.Count > 0 ? " (" + string.Join(", ", anchors.Select(a => a.Name)) + ")" : "")}\n");

            if (!ShilpiConfig.IsEnabled)
            {
                ed.WriteMessage("ShilpiDB sync: DISABLED (ACCELDRAW_SHILPID_ADDR not set)\n");
                return;
            }

            string address = ShilpiConfig.ServerAddress;
            try
            {
                using (ShilpiDbClient.Connect(address))
                {
                    ed.WriteMessage($"ShilpiDB sync: ENABLED, connected to {address}\n");
                }
            }
            catch (ShilpiDbException ex)
            {
                ed.WriteMessage($"ShilpiDB sync: ENABLED but unreachable at {address} ({ex.Message})\n");
            }
        }
    }
}
