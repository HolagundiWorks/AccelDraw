using AccelDraw.Geometry;
using AccelDraw.Plugin.AutoCAD;
using AccelDraw.Snapshot;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Runtime;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>
    /// ACCELDRAW_ANCHOR: define or list the project's named floor anchors (e.g. "Ground Floor",
    /// "First Floor"), shared across every drawing that saves into the same project's snapshots
    /// folder. ACCELDRAW_SAVE can record which anchor a snapshot was taken relative to;
    /// ACCELDRAW_RESTORE can use that to follow the anchor if it's later redefined.
    /// </summary>
    public class AnchorCommand
    {
        [CommandMethod("ACCELDRAW_ANCHOR")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var ed = doc.Editor;

            var pko = new PromptKeywordOptions("\nAnchor: ");
            pko.Keywords.Add("Define");
            pko.Keywords.Add("List");
            pko.Keywords.Default = "List";
            pko.AllowNone = true;
            var kwResult = ed.GetKeywords(pko);
            if (kwResult.Status != PromptStatus.OK && kwResult.Status != PromptStatus.None)
                return;

            string mode = string.IsNullOrEmpty(kwResult.StringResult) ? "List" : kwResult.StringResult;
            var store = new FloorAnchorStore(DrawingContext.ProjectAnchorsPath(doc));

            if (mode == "Define")
            {
                var nameResult = ed.GetString(new PromptStringOptions("\nFloor anchor name: ") { AllowSpaces = true });
                if (nameResult.Status != PromptStatus.OK || string.IsNullOrWhiteSpace(nameResult.StringResult))
                    return;

                var pointResult = ed.GetPoint("\nAnchor point: ");
                if (pointResult.Status != PromptStatus.OK)
                    return;

                store.Set(new FloorAnchor
                {
                    Name = nameResult.StringResult.Trim(),
                    Origin = new Point3D(pointResult.Value.X, pointResult.Value.Y, pointResult.Value.Z)
                });

                ed.WriteMessage($"\nFloor anchor '{nameResult.StringResult.Trim()}' saved.\n");
                return;
            }

            var anchors = store.List();
            if (anchors.Count == 0)
            {
                ed.WriteMessage("\n(no floor anchors defined yet — run ACCELDRAW_ANCHOR Define)\n");
                return;
            }

            ed.WriteMessage("\nFLOOR ANCHORS\n");
            foreach (var anchor in anchors)
                ed.WriteMessage($"\n{anchor.Name}\n  ({anchor.Origin.X:R}, {anchor.Origin.Y:R}, {anchor.Origin.Z:R})\n");
        }
    }
}
