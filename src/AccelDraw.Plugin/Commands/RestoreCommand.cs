using System.IO;
using AccelDraw.Plugin.AutoCAD;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Runtime;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>
    /// ACCELDRAW_RESTORE (spec section 19): clone a snapshot's entities into the current drawing's
    /// model space using their stored WCS position, independent of the active UCS.
    /// </summary>
    public class RestoreCommand
    {
        [CommandMethod("ACCELDRAW_RESTORE")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var db = doc.Database;
            var ed = doc.Editor;

            string snapshotId = SnapshotPrompt.PromptForSnapshotId(ed, doc, "Snapshot to restore");
            if (snapshotId == null)
                return;

            var store = new SnapshotStore(DrawingContext.SnapshotsDirectory(doc));
            var reader = new SnapshotReader();
            var snapshot = reader.Load(store.PackagePathFor(snapshotId));

            Database sideDb = null;
            try
            {
                sideDb = new Database(false, true);
                sideDb.ReadDwgFile(snapshot.ExtractedDwgPath, FileOpenMode.OpenForReadAndAllShare, false, null);

                TransactionHelper.RunTransacted(db, tr =>
                {
                    var sourceIds = ModelSpaceObjectIds(sideDb);
                    var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                    var destBtr = bt[BlockTableRecord.ModelSpace];

                    EntityCloner.CloneInto(sideDb, sourceIds, db, destBtr);
                });

                ed.WriteMessage($"\nSnapshot {snapshotId} restored into the current drawing.\n");
            }
            finally
            {
                sideDb?.Dispose();
                if (File.Exists(snapshot.ExtractedDwgPath))
                    File.Delete(snapshot.ExtractedDwgPath);
            }
        }

        internal static System.Collections.Generic.List<ObjectId> ModelSpaceObjectIds(Database sideDb)
        {
            var ids = new System.Collections.Generic.List<ObjectId>();
            using (var tr = sideDb.TransactionManager.StartTransaction())
            {
                var bt = (BlockTable)tr.GetObject(sideDb.BlockTableId, OpenMode.ForRead);
                var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForRead);
                foreach (ObjectId id in ms)
                    ids.Add(id);
                tr.Commit();
            }
            return ids;
        }
    }
}
