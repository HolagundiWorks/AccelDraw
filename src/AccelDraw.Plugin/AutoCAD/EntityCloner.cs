using System.Collections.Generic;
using System.Linq;
using Autodesk.AutoCAD.DatabaseServices;

namespace AccelDraw.Plugin.AutoCAD
{
    /// <summary>
    /// Wraps AutoCAD's WblockCloneObjects to move entities between databases while preserving
    /// their exact WCS position (spec section 5A: the native representation must preserve exact
    /// AutoCAD restoration, blocks, and entity-specific behaviour — a deep clone via Wblock is the
    /// only reliable way to do that, as opposed to re-deriving entities from normalized geometry).
    /// </summary>
    public static class EntityCloner
    {
        /// <summary>Creates a brand-new side database containing deep clones of the given entities' model space.</summary>
        public static Database CloneToNewDatabase(Database sourceDb, IEnumerable<ObjectId> ids)
        {
            var destDb = new Database(true, true);
            var idsToClone = new ObjectIdCollection(ids.ToArray());
            var mapping = new IdMapping();

            using (var trDest = destDb.TransactionManager.StartTransaction())
            {
                var bt = (BlockTable)trDest.GetObject(destDb.BlockTableId, OpenMode.ForRead);
                var destBtr = (BlockTableRecord)trDest.GetObject(bt[BlockTableRecord.ModelSpace], OpenMode.ForWrite);

                sourceDb.WblockCloneObjects(idsToClone, destBtr.ObjectId, mapping, DuplicateRecordCloning.Replace, false);

                trDest.Commit();
            }

            return destDb;
        }

        /// <summary>
        /// Clones the given entities (from sourceDb's model space) into destOwnerId (a block table
        /// record owned by destDb, typically its model space). Returns the id mapping so the caller
        /// can look up newly created entities, e.g. to reassign their layer for an overlay.
        /// </summary>
        public static IdMapping CloneInto(Database sourceDb, IEnumerable<ObjectId> ids, Database destDb, ObjectId destOwnerId)
        {
            var idsToClone = new ObjectIdCollection(ids.ToArray());
            var mapping = new IdMapping();

            sourceDb.WblockCloneObjects(idsToClone, destOwnerId, mapping, DuplicateRecordCloning.Replace, false);

            return mapping;
        }

        public static IEnumerable<ObjectId> ClonedIds(IdMapping mapping)
        {
            foreach (IdPair pair in mapping)
            {
                if (pair.IsCloned)
                    yield return pair.Value;
            }
        }
    }
}
