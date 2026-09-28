using System;
using System.IO;
using System.Reflection;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Runtime;
using AccelDraw.Plugin.UI;

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

            LoadLegacyLispTools(doc);
            LegacyToolsRibbon.Add();
        }

        public void Terminate()
        {
            LegacyToolsRibbon.Remove();
        }

        /// <summary>
        /// Auto-loads the legacy HCW/AccelDraw LISP toolkit (lisp/, copied
        /// next to this assembly) the same way acaddoc.lsp would, so the
        /// ribbon buttons in <see cref="LegacyToolsRibbon"/> have commands
        /// to call as soon as AccelDraw is NETLOADed.
        /// </summary>
        private static void LoadLegacyLispTools(Document doc)
        {
            if (doc == null) return;

            var pluginDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            var lispDir = Path.Combine(pluginDir ?? string.Empty, "lisp") + Path.DirectorySeparatorChar;
            var loader = Path.Combine(lispDir, "AccelDraw_LoadTools.lsp");
            if (!File.Exists(loader)) return;

            var lispDirEscaped = lispDir.Replace("\\", "\\\\");
            var loaderEscaped = loader.Replace("\\", "\\\\");
            doc.SendStringToExecute(
                $"(setq *AccelDraw:LispDir* \"{lispDirEscaped}\") (load \"{loaderEscaped}\") ",
                true, false, true);
        }
    }
}
