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
    ///
    /// <see cref="EnsureOn"/>/<see cref="EnsureOff"/> are reused by <see cref="RestoreCommand"/>'s
    /// partial-restore flow: overlay first, let the user select which overlaid entities to keep,
    /// restore just those, then clear whatever overlay is left.
    /// </summary>
    public class OverlayCommand
    {
        internal const string OverlayLayerName = "AccelDraw$OVERLAY";

        [CommandMethod("ACCELDRAW_OVERLAY")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var db = doc.Database;
            var ed = doc.Editor;

            if (IsOn(db))
            {
                EnsureOff(db);
                ed.WriteMessage("\nOverlay OFF\n");
                return;
            }

            string snapshotId = SnapshotPrompt.PromptForSnapshotId(ed, doc, "Snapshot to overlay");
            if (snapshotId == null)
                return;

            EnsureOn(doc, snapshotId);
            ed.WriteMessage($"\nOverlay ON ({snapshotId})\n");
        }

        /// <summary>Overlays the given snapshot if no overlay is currently showing. No-op if one already is.</summary>
        internal static void EnsureOn(Document doc, string snapshotId)
        {
            var db = doc.Database;
            if (IsOn(db))
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

                    foreach (var newId in EntityCloner.ClonedEntityIds(tr, mapping))
                    {
                        var entity = (Entity)tr.GetObject(newId, OpenMode.ForWrite);
                        entity.Layer = OverlayLayerName;
                    }
                });
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

        internal static bool IsOn(Database db)
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

        /// <summary>Erases every entity still on the overlay layer. Safe to call when overlay is already off.</summary>
        internal static void EnsureOff(Database db)
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

                // Entity.Erase() throws eOnLockedLayer on a locked layer (found live: NETLOAD
                // acceptance test, "eOnLockedLayer" on the very first ON->OFF cycle) — unlock for
                // the erase, then relock so the layer's still locked next time overlay turns on.
                var layerRecord = (LayerTableRecord)tr.GetObject(layerId, OpenMode.ForWrite);
                bool wasLocked = layerRecord.IsLocked;
                layerRecord.IsLocked = false;

                foreach (var id in toErase)
                {
                    var ent = (Entity)tr.GetObject(id, OpenMode.ForWrite);
                    ent.Erase();
                }

                layerRecord.IsLocked = wasLocked;
            });
        }
    }
}
