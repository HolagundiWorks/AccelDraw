using AccelDraw.Bridge;
using AccelDraw.Plugin.AutoCAD;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Runtime;

namespace AccelDraw.Plugin.Commands
{
    /// <summary>ACCELDRAW_SHILPI_STATUS: reports whether ShilpiDB sync is configured and reachable.</summary>
    public class ShilpiStatusCommand
    {
        [CommandMethod("ACCELDRAW_SHILPI_STATUS")]
        public void Execute()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            var ed = doc.Editor;

            if (!ShilpiConfig.IsEnabled)
            {
                ed.WriteMessage("\nShilpiDB sync: DISABLED (ACCELDRAW_SHILPID_ADDR not set)\n");
                return;
            }

            string address = ShilpiConfig.ServerAddress;
            try
            {
                using (ShilpiDbClient.Connect(address))
                {
                    ed.WriteMessage($"\nShilpiDB sync: ENABLED, connected to {address}\n");
                }
            }
            catch (ShilpiDbException ex)
            {
                ed.WriteMessage($"\nShilpiDB sync: ENABLED but unreachable at {address} ({ex.Message})\n");
            }
        }
    }
}
