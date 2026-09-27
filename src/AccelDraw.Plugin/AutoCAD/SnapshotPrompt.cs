using System.Linq;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.EditorInput;

namespace AccelDraw.Plugin.AutoCAD
{
    /// <summary>Shared "which snapshot?" prompt used by ACCELDRAW_OVERLAY / ACCELDRAW_COMPARE / ACCELDRAW_RESTORE.</summary>
    public static class SnapshotPrompt
    {
        /// <summary>Returns the chosen snapshot id, or null if the user cancelled or none exist.</summary>
        public static string PromptForSnapshotId(Editor ed, Document doc, string promptLabel)
        {
            var store = new SnapshotStore(DrawingContext.SnapshotsDirectory(doc));
            var manifests = store.ListManifests().ToList();

            if (manifests.Count == 0)
            {
                ed.WriteMessage("\n(no snapshots yet — run ACCELDRAW_SAVE)\n");
                return null;
            }

            string defaultId = manifests.Last().SnapshotId;
            var pso = new PromptStringOptions($"\n{promptLabel} <{defaultId}>: ") { AllowSpaces = false };
            var result = ed.GetString(pso);
            if (result.Status != PromptStatus.OK)
                return null;

            string snapshotId = string.IsNullOrWhiteSpace(result.StringResult) ? defaultId : result.StringResult.Trim();

            if (!store.Exists(snapshotId))
            {
                ed.WriteMessage($"\nNo snapshot named '{snapshotId}'. Available: {string.Join(", ", manifests.Select(m => m.SnapshotId))}\n");
                return null;
            }

            return snapshotId;
        }
    }
}
