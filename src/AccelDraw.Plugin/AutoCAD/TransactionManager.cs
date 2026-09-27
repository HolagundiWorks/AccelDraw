using System;
using Autodesk.AutoCAD.DatabaseServices;

namespace AccelDraw.Plugin.AutoCAD
{
    /// <summary>
    /// Runs a unit of work inside an AutoCAD transaction with explicit commit/abort discipline
    /// (spec section 20): on any exception the transaction is aborted so the drawing is never left
    /// partially modified, and the exception is rethrown for the caller to report.
    /// </summary>
    public static class TransactionHelper
    {
        public static void RunTransacted(Database database, Action<Transaction> work)
        {
            using (var tr = database.TransactionManager.StartTransaction())
            {
                try
                {
                    work(tr);
                    tr.Commit();
                }
                catch
                {
                    tr.Abort();
                    throw;
                }
            }
        }

        public static T RunTransacted<T>(Database database, Func<Transaction, T> work)
        {
            using (var tr = database.TransactionManager.StartTransaction())
            {
                try
                {
                    var result = work(tr);
                    tr.Commit();
                    return result;
                }
                catch
                {
                    tr.Abort();
                    throw;
                }
            }
        }
    }
}
