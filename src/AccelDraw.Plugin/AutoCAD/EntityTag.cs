using Autodesk.AutoCAD.DatabaseServices;

namespace AccelDraw.Plugin.AutoCAD
{
    /// <summary>
    /// Stamps each entity with the AutoCAD handle it had in the *original* drawing at save time,
    /// via XData. Handles are only stable within one database — cloning a snapshot's side DWG a
    /// second time (e.g. for an overlay) assigns fresh handles in the destination — but XData
    /// survives every clone/copy AutoCAD does, so this is the one identity that reliably travels
    /// from "entity the user drew" through the side DB all the way to an overlay clone. Partial
    /// restore (<see cref="RestoreCommand"/>) reads it back to look up the entity's original
    /// properties in vectors.json by <c>SourceHandle</c>, without depending on handle-preservation
    /// behavior that AutoCAD doesn't actually guarantee.
    /// </summary>
    public static class EntityTag
    {
        private const string AppName = "ACCELDRAW";

        public static void EnsureRegistered(Database db, Transaction tr)
        {
            var regTable = (RegAppTable)tr.GetObject(db.RegAppTableId, OpenMode.ForRead);
            if (regTable.Has(AppName))
                return;

            regTable.UpgradeOpen();
            var record = new RegAppTableRecord { Name = AppName };
            regTable.Add(record);
            tr.AddNewlyCreatedDBObject(record, true);
        }

        public static void WriteSourceHandle(Transaction tr, Database db, ObjectId entityId, string sourceHandle)
        {
            EnsureRegistered(db, tr);
            var entity = (Entity)tr.GetObject(entityId, OpenMode.ForWrite);
            using (var rb = new ResultBuffer(
                new TypedValue((int)DxfCode.ExtendedDataRegAppName, AppName),
                new TypedValue((int)DxfCode.ExtendedDataAsciiString, sourceHandle)))
            {
                entity.XData = rb;
            }
        }

        /// <summary>Returns the tagged original source handle, or null if this entity was never tagged.</summary>
        public static string ReadSourceHandle(Transaction tr, ObjectId entityId)
        {
            var entity = (Entity)tr.GetObject(entityId, OpenMode.ForRead);
            using (var rb = entity.GetXDataForApplication(AppName))
            {
                if (rb == null)
                    return null;

                var values = rb.AsArray();
                return values.Length >= 2 ? values[1].Value as string : null;
            }
        }
    }
}
