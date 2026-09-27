using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Runtime;

namespace AccelDraw.Plugin
{
    public class PluginEntry : IExtensionApplication
    {
        public void Initialize()
        {
            var doc = Application.DocumentManager.MdiActiveDocument;
            doc?.Editor.WriteMessage(
                "\nAccelDraw loaded. Commands: ACCELDRAW_SAVE, ACCELDRAW_SNAPSHOTS, ACCELDRAW_OVERLAY, " +
                "ACCELDRAW_COMPARE, ACCELDRAW_RESTORE, ACCELDRAW_ANCHOR, ACCELDRAW_STATUS, " +
                "ACCELDRAW_SHILPI_STATUS, ACCELDRAW_SHILPI_PUSH.\n");
        }

        public void Terminate()
        {
        }
    }
}
