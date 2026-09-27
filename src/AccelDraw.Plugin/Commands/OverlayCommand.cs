using System.Collections.Generic;
using AccelDraw.Plugin.AutoCAD;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Colors;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Runtime;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>
    /// ACCELDRAW_OVERLAY (spec section 16): toggles a non-destructive, spatially-aligned overlay of a
    /// stored snapshot on top of the current drawing, on a dedicated temporary layer. Never
    /// modifies the source drawing beyond that temporary layer's contents.
    /// </summary>
    public class OverlayCommand
    {
        private const string OverlayLayerName = "AccelDraw$OVERLAY";

        [CommandMethod("ACCELDRAW_OVERLAY")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var db = doc.Database;
            var ed = doc.Editor;

            if (OverlayIsOn(db))
            {
                TurnOff(db);
                ed.WriteMessage("\nOverlay OFF\n");
                return;
            }

            string snapshotId = SnapshotPrompt.PromptForSnapshotId(ed, doc, "Snapshot to overlay");
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

                var sourceIds = RestoreCommand.ModelSpaceObjectIds(sideDb);

                TransactionHelper.RunTransacted(db, tr =>
                {
                    EnsureOverlayLayer(db, tr);

                    var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                    var destBtrId = bt[BlockTableRecord.ModelSpace];

                    var mapping = EntityCloner.CloneInto(sideDb, sourceIds, db, destBtrId);

                    foreach (var newId in EntityCloner.ClonedIds(mapping))
                    {
                        var entity = (Entity)tr.GetObject(newId, OpenMode.ForWrite);
                        entity.Layer = OverlayLayerName;
                    }
                });

                ed.WriteMessage($"\nOverlay ON ({snapshotId})\n");
            }
            finally
            {
                sideDb?.Dispose();
                if (System.IO.File.Exists(snapshot.ExtractedDwgPath))
                    System.IO.File.Delete(snapshot.ExtractedDwgPath);
            }
        }

        private static void EnsureOverlayLayer(Database db, Transaction tr)
        {
            var lt = (LayerTable)tr.GetObject(db.LayerTableId, OpenMode.ForRead);
            if (lt.Has(OverlayLayerName))
                return;

            lt.UpgradeOpen();
            var ltr = new LayerTableRecord
            {
                Name = OverlayLayerName,
                Color = Color.FromColorIndex(ColorMethod.ByAci, 3),
                IsLocked = true
            };
            lt.Add(ltr);
            tr.AddNewlyCreatedDBObject(ltr, true);
        }

        private static bool OverlayIsOn(Database db)
        {
            return TransactionHelper.RunTransacted(db, tr =>
            {
                var lt = (LayerTable)tr.GetObject(db.LayerTableId, OpenMode.ForRead);
                if (!lt.Has(OverlayLayerName))
                    return false;

                var layerId = lt[OverlayLayerName];
                var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForRead);
                foreach (ObjectId id in ms)
                {
                    var ent = (Entity)tr.GetObject(id, OpenMode.ForRead);
                    if (ent.LayerId == layerId)
                        return true;
                }
                return false;
            });
        }

        private static void TurnOff(Database db)
        {
            TransactionHelper.RunTransacted(db, tr =>
            {
                var lt = (LayerTable)tr.GetObject(db.LayerTableId, OpenMode.ForRead);
                if (!lt.Has(OverlayLayerName))
                    return;

                var layerId = lt[OverlayLayerName];
                var bt = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                var ms = (BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForRead);

                var toErase = new List<ObjectId>();
                foreach (ObjectId id in ms)
                {
                    var ent = (Entity)tr.GetObject(id, OpenMode.ForRead);
                    if (ent.LayerId == layerId)
                        toErase.Add(id);
                }

                foreach (var id in toErase)
                {
                    var ent = (Entity)tr.GetObject(id, OpenMode.ForWrite);
                    ent.Erase();
                }
            });
        }
    }
}
