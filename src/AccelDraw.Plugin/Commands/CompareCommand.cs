using System.IO;
using AccelDraw.Geometry;
using AccelDraw.Plugin.AutoCAD;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Runtime;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>
    /// ACCELDRAW_COMPARE (spec sections 17-18): deterministic, tolerance-based geometric comparison
    /// between a stored snapshot and the current drawing's model space. No architectural interpretation.
    /// </summary>
    public class CompareCommand
    {
        [CommandMethod("ACCELDRAW_COMPARE")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var db = doc.Database;
            var ed = doc.Editor;

            string snapshotId = SnapshotPrompt.PromptForSnapshotId(ed, doc, "Snapshot to compare against current drawing");
            if (snapshotId == null)
                return;

            var store = new SnapshotStore(DrawingContext.SnapshotsDirectory(doc));
            var reader = new SnapshotReader();
            var snapshot = reader.Load(store.PackagePathFor(snapshotId));
            if (File.Exists(snapshot.ExtractedDwgPath))
                File.Delete(snapshot.ExtractedDwgPath);

            var entityReader = new EntityReader();
            var currentIds = RestoreCommand.ModelSpaceObjectIds(db);
            var current = entityReader.Extract(db, currentIds);
            current.Entities.RemoveAll(e => e.IsUnsupported);

            var comparer = new GeometryComparer();
            var result = comparer.Compare(snapshot.Vectors, current);

            ed.WriteMessage($"\nCOMPARE — {snapshotId} vs current drawing\n");
            ed.WriteMessage($"UNCHANGED: {result.CountOf(ChangeType.Unchanged)}\n");
            ed.WriteMessage($"MOVED:     {result.CountOf(ChangeType.Moved)}\n");
            ed.WriteMessage($"MODIFIED:  {result.CountOf(ChangeType.Modified)}\n");
            ed.WriteMessage($"ADDED:     {result.CountOf(ChangeType.Added)}\n");
            ed.WriteMessage($"REMOVED:   {result.CountOf(ChangeType.Removed)}\n");

            foreach (var comparison in result.Comparisons)
            {
                if (comparison.ChangeType == ChangeType.Unchanged)
                    continue;

                var entity = comparison.Current ?? comparison.Previous;
                ed.WriteMessage($"  {comparison.ChangeType.ToString().ToUpperInvariant()}  {entity.EntityType} handle={entity.SourceHandle}\n");
            }
        }
    }
}
