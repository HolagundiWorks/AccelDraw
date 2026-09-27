using AccelDraw.Bridge;
using AccelDraw.Plugin.AutoCAD;
using AccelDraw.ShilpiDb;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Runtime;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>
    /// ACCELDRAW_SHILPI_PUSH: sends one already-saved snapshot's vector entities into ShilpiDB —
    /// the shared store AADT also targets — over the native bridge (see bridge/README.md). Opt-in:
    /// requires ACCELDRAW_SHILPID_ADDR to point at a running shilpid. The local .adw package is
    /// untouched either way; this is an additional sync, not a replacement for it (yet — see
    /// docs/ROADMAP.md for making ShilpiDB the primary store).
    /// </summary>
    public class ShilpiPushCommand
    {
        [CommandMethod("ACCELDRAW_SHILPI_PUSH")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var ed = doc.Editor;

            if (!ShilpiConfig.IsEnabled)
            {
                ed.WriteMessage("\nShilpiDB sync is disabled. Set ACCELDRAW_SHILPID_ADDR (e.g. 127.0.0.1:7420) and restart AutoCAD.\n");
                return;
            }

            string snapshotId = SnapshotPrompt.PromptForSnapshotId(ed, doc, "Snapshot to push to ShilpiDB");
            if (snapshotId == null)
                return;

            var store = new SnapshotStore(DrawingContext.SnapshotsDirectory(doc));
            var reader = new SnapshotReader();
            var snapshot = reader.Load(store.PackagePathFor(snapshotId));
            if (System.IO.File.Exists(snapshot.ExtractedDwgPath))
                System.IO.File.Delete(snapshot.ExtractedDwgPath);

            try
            {
                using (var client = ShilpiDbClient.Connect(ShilpiConfig.ServerAddress))
                {
                    var sync = new ShilpiSnapshotSync(client);
                    sync.Push(snapshot.Vectors);
                }

                ed.WriteMessage($"\nPushed {snapshot.Vectors.Entities.Count} entities from {snapshotId} to ShilpiDB at {ShilpiConfig.ServerAddress}.\n");
            }
            catch (ShilpiDbException ex)
            {
                ed.WriteMessage($"\nShilpiDB push failed: {ex.Message}\n");
            }
        }
    }
}
