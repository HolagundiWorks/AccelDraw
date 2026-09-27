using AccelDraw.Plugin.AutoCAD;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Runtime;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>ACCELDRAW_SNAPSHOTS (spec section 14): list available snapshots for the current drawing.</summary>
    public class SnapshotsCommand
    {
        [CommandMethod("ACCELDRAW_SNAPSHOTS")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var ed = doc.Editor;
            var store = new SnapshotStore(DrawingContext.SnapshotsDirectory(doc));

            ed.WriteMessage("\nTIME MACHINE\n");

            bool any = false;
            foreach (var manifest in store.ListManifests())
            {
                any = true;
                ed.WriteMessage(
                    $"\n{manifest.SnapshotId}\n{manifest.Name}\n{manifest.CreatedAt:dd MMM yyyy}\n{manifest.Selection.EntityCount} entities\n");

                if (manifest.FloorAnchor != null)
                    ed.WriteMessage($"anchor: {manifest.FloorAnchor.Name}\n");

                if (manifest.Extent?.Min != null && manifest.Extent.Max != null)
                {
                    var min = manifest.Extent.Min;
                    var max = manifest.Extent.Max;
                    ed.WriteMessage($"extent: ({min[0]:F1}, {min[1]:F1}) - ({max[0]:F1}, {max[1]:F1})\n");
                }
            }

            if (!any)
                ed.WriteMessage("\n(no snapshots yet — run ACCELDRAW_SAVE)\n");
        }
    }
}
