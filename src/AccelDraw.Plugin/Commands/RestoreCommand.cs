using System.Collections.Generic;
using System.IO;
using System.Linq;
using AccelDraw.Plugin.AutoCAD;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using Vec = AccelDraw.Geometry;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>
    /// ACCELDRAW_RESTORE (spec section 19, extended): clone a snapshot's entities into the current
    /// drawing's model space, either the whole thing (Full) or a user-picked subset (Partial —
    /// overlays the snapshot first, on the locked overlay layer, and restores only what the user
    /// selects from it). Full restore can additionally land at the snapshot's original point, an
    /// explicitly picked point, or — if the snapshot recorded a floor anchor — wherever that
    /// anchor currently sits, so a snapshot follows its floor if the anchor gets redefined.
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

            var modeOptions = new PromptKeywordOptions("\nRestore mode: ");
            modeOptions.Keywords.Add("Full");
            modeOptions.Keywords.Add("Partial");
            modeOptions.Keywords.Default = "Full";
            modeOptions.AllowNone = true;
            var modeResult = ed.GetKeywords(modeOptions);
            if (modeResult.Status != PromptStatus.OK && modeResult.Status != PromptStatus.None)
                return;

            string mode = string.IsNullOrEmpty(modeResult.StringResult) ? "Full" : modeResult.StringResult;

            if (mode == "Partial")
            {
                ExecutePartial(doc, db, ed, snapshotId);
                return;
            }

            ExecuteFull(doc, db, ed, snapshotId);
        }

        private void ExecuteFull(Document doc, Database db, Editor ed, string snapshotId)
        {
            var store = new SnapshotStore(DrawingContext.SnapshotsDirectory(doc));
            var reader = new SnapshotReader();
            var snapshot = reader.Load(store.PackagePathFor(snapshotId));

            Vector3d? translation = PromptTranslation(doc, ed, snapshot);
            if (translation == null)
                return;

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

                    var mapping = EntityCloner.CloneInto(sideDb, sourceIds, db, destBtr);

                    if (translation.HasValue && !translation.Value.IsZeroLength())
                    {
                        var displacement = Matrix3d.Displacement(translation.Value);
                        foreach (var newId in EntityCloner.ClonedEntityIds(tr, mapping))
                        {
                            var entity = (Entity)tr.GetObject(newId, OpenMode.ForWrite);
                            entity.TransformBy(displacement);
                        }
                    }
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

        /// <summary>
        /// Asks where to land the restore: at the snapshot's original point (no translation), at a
        /// freshly picked point, or — if available — wherever the snapshot's floor anchor currently
        /// sits in this project. Returns null (with the prompt left as cancelled) if the user backs out.
        /// </summary>
        private Vector3d? PromptTranslation(Document doc, Editor ed, AccelDraw.Snapshot.LoadedSnapshot snapshot)
        {
            var manifest = snapshot.Manifest;
            bool hasAnchor = manifest.FloorAnchor != null;

            var options = new PromptKeywordOptions("\nRestore at: ");
            options.Keywords.Add("Original");
            options.Keywords.Add("Pick");
            if (hasAnchor)
                options.Keywords.Add("Anchor");
            options.Keywords.Default = "Original";
            options.AllowNone = true;
            var result = ed.GetKeywords(options);
            if (result.Status != PromptStatus.OK && result.Status != PromptStatus.None)
                return null;

            string choice = string.IsNullOrEmpty(result.StringResult) ? "Original" : result.StringResult;
            var basePoint = manifest.Selection.BasePoint;
            var original = new Point3d(basePoint[0], basePoint[1], basePoint[2]);

            if (choice == "Pick")
            {
                var pointResult = ed.GetPoint("\nNew anchor point: ");
                if (pointResult.Status != PromptStatus.OK)
                    return null;
                return pointResult.Value - original;
            }

            if (choice == "Anchor" && hasAnchor)
            {
                var anchorStore = new FloorAnchorStore(DrawingContext.ProjectAnchorsPath(doc));
                var currentAnchor = anchorStore.Get(manifest.FloorAnchor.Name);
                if (currentAnchor == null)
                {
                    ed.WriteMessage($"\nFloor anchor '{manifest.FloorAnchor.Name}' is not defined in this project — restoring at the original point instead.\n");
                    return new Vector3d(0, 0, 0);
                }

                var savedOrigin = manifest.FloorAnchor.OriginAtSave;
                var delta = new Vector3d(
                    currentAnchor.Origin.X - savedOrigin[0],
                    currentAnchor.Origin.Y - savedOrigin[1],
                    currentAnchor.Origin.Z - savedOrigin[2]);
                return delta;
            }

            return new Vector3d(0, 0, 0);
        }

        private void ExecutePartial(Document doc, Database db, Editor ed, string snapshotId)
        {
            var store = new SnapshotStore(DrawingContext.SnapshotsDirectory(doc));
            var reader = new SnapshotReader();
            var snapshot = reader.Load(store.PackagePathFor(snapshotId));
            if (File.Exists(snapshot.ExtractedDwgPath))
                File.Delete(snapshot.ExtractedDwgPath);

            bool overlayWasAlreadyOn = OverlayCommand.IsOn(db);
            if (!overlayWasAlreadyOn)
                OverlayCommand.EnsureOn(doc, snapshotId);

            var filter = new SelectionFilter(new[]
            {
                new TypedValue((int)DxfCode.LayerName, OverlayCommand.OverlayLayerName)
            });
            var pso = new PromptSelectionOptions { MessageForAdding = "\nSelect entities to restore from the overlay:" };
            var selResult = ed.GetSelection(pso, filter);

            if (selResult.Status != PromptStatus.OK || selResult.Value.Count == 0)
            {
                ed.WriteMessage("\nACCELDRAW_RESTORE (partial) cancelled: nothing selected.\n");
                if (!overlayWasAlreadyOn)
                    OverlayCommand.EnsureOff(db);
                return;
            }

            var byHandle = snapshot.Vectors.Entities.ToDictionary(e => e.SourceHandle);
            int restored = 0;

            TransactionHelper.RunTransacted(db, tr =>
            {
                foreach (ObjectId id in selResult.Value.GetObjectIds())
                {
                    string sourceHandle = EntityTag.ReadSourceHandle(tr, id);
                    if (sourceHandle == null || !byHandle.TryGetValue(sourceHandle, out var vectorEntity))
                        continue;

                    var entity = (Entity)tr.GetObject(id, OpenMode.ForWrite);
                    ApplyOriginalProperties(db, tr, entity, vectorEntity.Properties);
                    restored++;
                }
            });

            OverlayCommand.EnsureOff(db);

            ed.WriteMessage($"\nRestored {restored} of {selResult.Value.Count} selected entities from {snapshotId} (with original layer/properties).\n");
        }

        private static void ApplyOriginalProperties(Database db, Transaction tr, Entity entity, Vec.EntityProperties properties)
        {
            if (properties == null)
                return;

            EnsureLayerExists(db, tr, properties.Layer);
            entity.Layer = properties.Layer;
            entity.ColorIndex = properties.Color;
            entity.Linetype = properties.Linetype;
            entity.LineWeight = (LineWeight)properties.Lineweight;
        }

        private static void EnsureLayerExists(Database db, Transaction tr, string layerName)
        {
            if (string.IsNullOrEmpty(layerName))
                return;

            var lt = (LayerTable)tr.GetObject(db.LayerTableId, OpenMode.ForRead);
            if (lt.Has(layerName))
                return;

            lt.UpgradeOpen();
            var ltr = new LayerTableRecord { Name = layerName };
            lt.Add(ltr);
            tr.AddNewlyCreatedDBObject(ltr, true);
        }

        internal static List<ObjectId> ModelSpaceObjectIds(Database sideDb)
        {
            var ids = new List<ObjectId>();
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
