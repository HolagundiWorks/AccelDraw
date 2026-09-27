using System;
using System.IO;
using System.Linq;
using AccelDraw.Plugin.AutoCAD;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Runtime;
using Vec = AccelDraw.Geometry;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>ACCELDRAW_SAVE (spec section 13): select entities, name and place a snapshot, package it as .adw.</summary>
    public class SaveCommand
    {
        [CommandMethod("ACCELDRAW_SAVE")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var db = doc.Database;
            var ed = doc.Editor;

            var pso = new PromptSelectionOptions { MessageForAdding = "\nSelect objects:" };
            var selResult = ed.GetSelection(pso);
            if (selResult.Status != PromptStatus.OK || selResult.Value.Count == 0)
            {
                ed.WriteMessage("\nACCELDRAW_SAVE cancelled: nothing selected.\n");
                return;
            }

            var nameResult = ed.GetString(new PromptStringOptions("\nSnapshot name: ") { AllowSpaces = true });
            if (nameResult.Status != PromptStatus.OK)
                return;

            var pointResult = ed.GetPoint("\nBase point: ");
            if (pointResult.Status != PromptStatus.OK)
                return;

            var selectedIds = selResult.Value.GetObjectIds();

            var reader = new EntityReader();
            var document = reader.Extract(db, selectedIds);
            document.BasePoint = new Vec.Point3D(pointResult.Value.X, pointResult.Value.Y, pointResult.Value.Z);

            var unsupported = document.Entities.Where(e => e.IsUnsupported).ToList();
            document.Entities = document.Entities.Where(e => !e.IsUnsupported).ToList();

            var store = new SnapshotStore(DrawingContext.SnapshotsDirectory(doc));
            string snapshotId = store.GenerateNextSnapshotId();

            foreach (var entity in document.Entities)
                entity.SnapshotEntityId = $"{snapshotId}/{entity.Id}";

            var manifest = new SnapshotManifest
            {
                SnapshotId = snapshotId,
                Name = nameResult.StringResult,
                CreatedAt = DateTimeOffset.Now,
                Drawing = new SnapshotManifest.DrawingInfo
                {
                    Name = DrawingContext.DrawingName(doc),
                    Fingerprint = DrawingContext.DrawingFingerprint(doc)
                },
                AutoCad = new SnapshotManifest.AutoCadInfo { Version = "2022" },
                Selection = new SnapshotManifest.SelectionInfo
                {
                    EntityCount = document.Entities.Count,
                    BasePoint = new[] { pointResult.Value.X, pointResult.Value.Y, pointResult.Value.Z }
                }
            };

            foreach (var entity in unsupported)
            {
                manifest.UnsupportedEntities.Add(new SnapshotManifest.UnsupportedEntity
                {
                    Handle = entity.SourceHandle,
                    ObjectType = entity.SourceObjectType
                });
            }

            string tempDwgPath = Path.Combine(Path.GetTempPath(), "acceldraw-save-" + Guid.NewGuid().ToString("N") + ".dwg");
            Database cloneDb = null;
            try
            {
                cloneDb = EntityCloner.CloneToNewDatabase(db, selectedIds);
                cloneDb.SaveAs(tempDwgPath, DwgVersion.Current);
            }
            finally
            {
                cloneDb?.Dispose();
            }

            try
            {
                var writer = new SnapshotWriter();
                writer.Write(store.Directory, manifest, document, tempDwgPath);
            }
            finally
            {
                if (File.Exists(tempDwgPath))
                    File.Delete(tempDwgPath);
            }

            ed.WriteMessage($"\n{manifest.Selection.EntityCount} entities captured");
            if (unsupported.Count > 0)
                ed.WriteMessage($" ({unsupported.Count} unsupported entity type(s) skipped in vectors.json, kept in snapshot.dwg)");
            ed.WriteMessage($".\n\nSnapshot created:\n{snapshotId}\n");
        }
    }
}
