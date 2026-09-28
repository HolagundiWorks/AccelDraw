using Autodesk.Windows;

namespace AccelDraw.Plugin.UI
{
    /// <summary>
    /// Ribbon tab exposing the legacy HCW/AccelDraw LISP toolkit (lisp/) as
    /// clickable buttons. AutoCAD's managed API no longer has a classic
    /// "ToolBar"/"ToolBarButton" type (that API was removed after the 2012
    /// era) — a ribbon tab is the direct modern replacement and needs no
    /// CUIX file, so it is built entirely from PluginEntry.Initialize().
    /// </summary>
    internal static class LegacyToolsRibbon
    {
        private const string TabId = "ACCELDRAW_LEGACY_TAB";
        private static RibbonTab _tab;

        public static void Add()
        {
            var ribbon = ComponentManager.Ribbon;
            if (ribbon == null || Find(ribbon) != null) return;

            _tab = new RibbonTab { Title = "AccelDraw Tools", Id = TabId };

            _tab.Panels.Add(BuildPanel("Area && Text", new[]
            {
                Button("Polyline\nArea", "POLYAREA", "Number selected polylines and draw an area table."),
                Button("Delete Area\nText", "DELETEAREATEXT", "Delete generated \"Area: n\" text objects."),
                Button("Fix Text\nOverlap", "FIXTXT", "Set uniform height and spacing on overlapping text."),
                Button("Text\nIncrement", "TextIncrement", "Copy a text object, incrementing its trailing number."),
            }));

            _tab.Panels.Add(BuildPanel("Rooms (Metric)", new[]
            {
                Button("Room\nSelector", "MROOM", "Pick a room type from an A-Z dialog and label it."),
                Button("Custom\nRoom", "MDO", "Label a room with a typed-in custom name."),
                Button("Area\nLabel", "MAR", "Add an area label to a selected polyline/rectangle."),
                Button("Room Tool\nSettings", "MSET", "Show current room-tool settings."),
            }));

            _tab.Panels.Add(BuildPanel("Blocks", new[]
            {
                Button("Window\nLabel", "WinLabel", "Label window blocks from their WNAME parameter."),
            }));

            _tab.Panels.Add(BuildPanel("Layers && Standards", new[]
            {
                Button("VH\nLayers", "VHLAYERS", "Create the VH Indian Architecture layer set."),
                Button("HCW\nLayers", "HCWLAYERS", "Create/update the HCW Layer Standard v4.0 layer set."),
                Button("BP Setup\n(BBMP)", "BPLTSTART", "Building Permission (BBMP BPAS/AutoPlan) drawing setup."),
                Button("BP Layer\nLegend", "BPLTLAYERS", "Place the Building Permission layer-reference legend."),
                Button("Layer\nMapper", "LAYERMAP", "Map existing layers onto standard layers and move entities across."),
            }));

            ribbon.Tabs.Add(_tab);
        }

        public static void Remove()
        {
            var ribbon = ComponentManager.Ribbon;
            var tab = ribbon == null ? null : Find(ribbon);
            if (tab != null) ribbon.Tabs.Remove(tab);
            _tab = null;
        }

        private static RibbonTab Find(RibbonControl ribbon)
        {
            foreach (RibbonTab tab in ribbon.Tabs)
            {
                if (tab.Id == TabId) return tab;
            }
            return null;
        }

        private static RibbonPanel BuildPanel(string title, RibbonButton[] buttons)
        {
            var source = new RibbonPanelSource { Title = title };
            foreach (var button in buttons) source.Items.Add(button);
            return new RibbonPanel { Source = source };
        }

        private static RibbonButton Button(string text, string lispCommand, string tooltip)
        {
            return new RibbonButton
            {
                Text = text,
                ShowText = true,
                ShowImage = false,
                Size = RibbonItemSize.Large,
                Orientation = System.Windows.Controls.Orientation.Vertical,
                ToolTip = tooltip,
                // ^C^C cancels any pending command first; the trailing space
                // "presses Enter" the same as typing the command and hitting Enter.
                CommandHandler = new RibbonCommandHandler(),
                CommandParameter = $"^C^C_{lispCommand} ",
            };
        }

        /// <summary>Runs a button's CommandParameter as a command-line macro string.</summary>
        private sealed class RibbonCommandHandler : System.Windows.Input.ICommand
        {
            public event System.EventHandler CanExecuteChanged { add { } remove { } }
            public bool CanExecute(object parameter) => true;

            public void Execute(object parameter)
            {
                var macro = parameter as string;
                var doc = Autodesk.AutoCAD.ApplicationServices.Application.DocumentManager.MdiActiveDocument;
                if (doc != null && !string.IsNullOrEmpty(macro))
                {
                    doc.SendStringToExecute(macro, true, false, true);
                }
            }
        }
    }
}
