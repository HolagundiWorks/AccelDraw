using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using AccelDraw.Bridge;
using AccelDraw.Geometry;
using AccelDraw.ShilpiDb;
using AccelDraw.Snapshot;
using Newtonsoft.Json;

namespace AccelDraw.Manager
{
    /// <summary>
    /// A standalone .NET desktop app for browsing/managing AccelDraw's Time Machine state without
    /// AutoCAD: .adw snapshots, project floor anchors, and the ShilpiDB connection — everything
    /// this session found painful to drive through AutoCAD's command line, in a real UI instead.
    /// Read/manage only: creating a new snapshot still needs AutoCAD (ACCELDRAW_SAVE), since that's
    /// the one step that requires live drawing geometry.
    /// </summary>
    public class MainForm : Form
    {
        private string _projectDir;
        private SnapshotStore _snapshotStore;
        private FloorAnchorStore _anchorStore;

        private Label _projectLabel;
        private TabControl _tabs;

        // Snapshots tab
        private DataGridView _snapshotGrid;
        private TextBox _snapshotDetail;
        private Button _pushButton;
        private Button _deleteSnapshotButton;

        // Floor anchors tab
        private DataGridView _anchorGrid;

        // ShilpiDB tab
        private TextBox _shilpiAddressBox;
        private Label _shilpiStatusLabel;
        private TextBox _shilpiLog;

        public MainForm()
        {
            Text = "AccelDraw Manager";
            Width = 1050;
            Height = 700;
            StartPosition = FormStartPosition.CenterScreen;

            BuildLayout();

            string envAddr = Environment.GetEnvironmentVariable("ACCELDRAW_SHILPID_ADDR");
            _shilpiAddressBox.Text = string.IsNullOrWhiteSpace(envAddr) ? "127.0.0.1:7420" : envAddr;
        }

        private void BuildLayout()
        {
            var topPanel = new Panel { Dock = DockStyle.Top, Height = 40 };
            var openButton = new Button { Text = "Open Project...", Left = 8, Top = 6, Width = 130 };
            openButton.Click += (s, e) => OpenProject();
            _projectLabel = new Label { Text = "(no project open)", Left = 150, Top = 12, Width = 850, AutoEllipsis = true };
            topPanel.Controls.Add(openButton);
            topPanel.Controls.Add(_projectLabel);

            _tabs = new TabControl { Dock = DockStyle.Fill };
            _tabs.TabPages.Add(BuildSnapshotsTab());
            _tabs.TabPages.Add(BuildAnchorsTab());
            _tabs.TabPages.Add(BuildShilpiTab());

            Controls.Add(_tabs);
            Controls.Add(topPanel);
        }

        private TabPage BuildSnapshotsTab()
        {
            var page = new TabPage("Snapshots");

            var split = new SplitContainer { Dock = DockStyle.Fill, SplitterDistance = 550 };

            _snapshotGrid = new DataGridView
            {
                Dock = DockStyle.Fill,
                AutoGenerateColumns = false,
                ReadOnly = true,
                AllowUserToAddRows = false,
                AllowUserToDeleteRows = false,
                SelectionMode = DataGridViewSelectionMode.FullRowSelect,
                MultiSelect = false
            };
            _snapshotGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Id", DataPropertyName = "SnapshotId", Width = 90 });
            _snapshotGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Name", DataPropertyName = "Name", Width = 140 });
            _snapshotGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Created", DataPropertyName = "CreatedDisplay", Width = 110 });
            _snapshotGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Entities", DataPropertyName = "EntityCount", Width = 60 });
            _snapshotGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Extent", DataPropertyName = "ExtentDisplay", Width = 220 });
            _snapshotGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Floor Anchor", DataPropertyName = "AnchorDisplay", Width = 100 });
            _snapshotGrid.SelectionChanged += (s, e) => ShowSelectedSnapshotDetail();

            var leftPanel = new Panel { Dock = DockStyle.Fill };
            var buttonBar = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 36, FlowDirection = FlowDirection.LeftToRight };
            var refreshButton = new Button { Text = "Refresh", AutoSize = true, Margin = new Padding(4) };
            refreshButton.Click += (s, e) => LoadSnapshots();
            _deleteSnapshotButton = new Button { Text = "Delete", Enabled = false, AutoSize = true, Margin = new Padding(4) };
            _deleteSnapshotButton.Click += (s, e) => DeleteSelectedSnapshot();
            _pushButton = new Button { Text = "Push to ShilpiDB", Enabled = false, AutoSize = true, Margin = new Padding(4) };
            _pushButton.Click += (s, e) => PushSelectedSnapshot();
            buttonBar.Controls.Add(refreshButton);
            buttonBar.Controls.Add(_deleteSnapshotButton);
            buttonBar.Controls.Add(_pushButton);
            leftPanel.Controls.Add(_snapshotGrid);
            leftPanel.Controls.Add(buttonBar);

            _snapshotDetail = new TextBox
            {
                Dock = DockStyle.Fill,
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Vertical,
                Font = new System.Drawing.Font("Consolas", 9)
            };

            split.Panel1.Controls.Add(leftPanel);
            split.Panel2.Controls.Add(_snapshotDetail);
            page.Controls.Add(split);
            return page;
        }

        private TabPage BuildAnchorsTab()
        {
            var page = new TabPage("Floor Anchors");
            var layout = new Panel { Dock = DockStyle.Fill };

            _anchorGrid = new DataGridView
            {
                Dock = DockStyle.Fill,
                AutoGenerateColumns = false,
                ReadOnly = true,
                AllowUserToAddRows = false,
                AllowUserToDeleteRows = false,
                SelectionMode = DataGridViewSelectionMode.FullRowSelect,
                MultiSelect = false
            };
            _anchorGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Name", DataPropertyName = "Name", Width = 200 });
            _anchorGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "X", DataPropertyName = "X", Width = 150 });
            _anchorGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Y", DataPropertyName = "Y", Width = 150 });
            _anchorGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Z", DataPropertyName = "Z", Width = 150 });

            var buttonBar = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 36 };
            var refreshButton = new Button { Text = "Refresh", AutoSize = true, Margin = new Padding(4) };
            refreshButton.Click += (s, e) => LoadAnchors();
            var addButton = new Button { Text = "Add / Update...", AutoSize = true, Margin = new Padding(4) };
            addButton.Click += (s, e) => AddOrUpdateAnchor();
            buttonBar.Controls.Add(refreshButton);
            buttonBar.Controls.Add(addButton);

            layout.Controls.Add(_anchorGrid);
            layout.Controls.Add(buttonBar);
            page.Controls.Add(layout);
            return page;
        }

        private TabPage BuildShilpiTab()
        {
            var page = new TabPage("ShilpiDB");
            var panel = new Panel { Dock = DockStyle.Fill };

            var addrLabel = new Label { Text = "shilpid address:", Left = 12, Top = 16, Width = 110 };
            _shilpiAddressBox = new TextBox { Left = 130, Top = 12, Width = 200 };
            var testButton = new Button { Text = "Test Connection", Left = 340, Top = 10, Width = 130 };
            testButton.Click += (s, e) => TestShilpiConnection();
            _shilpiStatusLabel = new Label { Text = "", Left = 480, Top = 16, Width = 400, ForeColor = System.Drawing.Color.DimGray };

            _shilpiLog = new TextBox
            {
                Left = 12,
                Top = 48,
                Width = 1000,
                Height = 560,
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Vertical,
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
                Font = new System.Drawing.Font("Consolas", 9)
            };

            panel.Controls.Add(addrLabel);
            panel.Controls.Add(_shilpiAddressBox);
            panel.Controls.Add(testButton);
            panel.Controls.Add(_shilpiStatusLabel);
            panel.Controls.Add(_shilpiLog);
            page.Controls.Add(panel);
            return page;
        }

        private void OpenProject()
        {
            using (var dialog = new FolderBrowserDialog { Description = "Select the project folder (the one containing 'snapshots\\' and 'floor-anchors.json')" })
            {
                if (dialog.ShowDialog(this) != DialogResult.OK)
                    return;

                _projectDir = dialog.SelectedPath;
                _projectLabel.Text = _projectDir;

                _snapshotStore = new SnapshotStore(Path.Combine(_projectDir, "snapshots"));
                _anchorStore = new FloorAnchorStore(Path.Combine(_projectDir, "floor-anchors.json"));

                LoadSnapshots();
                LoadAnchors();
            }
        }

        private void LoadSnapshots()
        {
            if (_snapshotStore == null)
                return;

            var rows = _snapshotStore.ListManifests()
                .Select(m => new SnapshotRow(m))
                .OrderByDescending(r => r.SnapshotId)
                .ToList();

            _snapshotGrid.DataSource = rows;
            _pushButton.Enabled = false;
            _deleteSnapshotButton.Enabled = false;
            _snapshotDetail.Text = "";
        }

        private void LoadAnchors()
        {
            if (_anchorStore == null)
                return;

            var rows = _anchorStore.List()
                .Select(a => new AnchorRow(a))
                .OrderBy(r => r.Name)
                .ToList();

            _anchorGrid.DataSource = rows;
        }

        private SnapshotRow SelectedSnapshot()
        {
            if (_snapshotGrid.CurrentRow?.DataBoundItem is SnapshotRow row)
                return row;
            return null;
        }

        private void ShowSelectedSnapshotDetail()
        {
            var row = SelectedSnapshot();
            _pushButton.Enabled = row != null;
            _deleteSnapshotButton.Enabled = row != null;

            if (row == null)
            {
                _snapshotDetail.Text = "";
                return;
            }

            _snapshotDetail.Text = JsonConvert.SerializeObject(row.Manifest, Formatting.Indented);
        }

        private void DeleteSelectedSnapshot()
        {
            var row = SelectedSnapshot();
            if (row == null)
                return;

            var confirm = MessageBox.Show(
                $"Delete snapshot {row.SnapshotId} (\"{row.Name}\")? This removes the .adw file — it cannot be undone.",
                "Delete snapshot", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (confirm != DialogResult.Yes)
                return;

            File.Delete(_snapshotStore.PackagePathFor(row.SnapshotId));
            LoadSnapshots();
        }

        private void PushSelectedSnapshot()
        {
            var row = SelectedSnapshot();
            if (row == null)
                return;

            string address = _shilpiAddressBox.Text.Trim();
            if (string.IsNullOrEmpty(address))
            {
                MessageBox.Show(this, "Enter a shilpid address on the ShilpiDB tab first.", "ShilpiDB", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            var reader = new SnapshotReader();
            var loaded = reader.Load(_snapshotStore.PackagePathFor(row.SnapshotId));
            if (File.Exists(loaded.ExtractedDwgPath))
                File.Delete(loaded.ExtractedDwgPath);

            ShilpiBbox? tileExtent = null;
            var extent = loaded.Manifest.Extent;
            if (extent?.Min != null && extent.Max != null)
                tileExtent = ShilpiBbox.FromCorners(extent.Min[0], extent.Min[1], extent.Max[0], extent.Max[1]);

            try
            {
                using (var client = ShilpiDbClient.Connect(address))
                {
                    var sync = new ShilpiSnapshotSync(client);
                    sync.Push(row.SnapshotId, tileExtent, loaded.Vectors);
                }

                AppendShilpiLog($"Pushed {loaded.Vectors.Entities.Count} entities from {row.SnapshotId} to {address}.");
                _tabs.SelectedIndex = 2;
            }
            catch (ShilpiDbException ex)
            {
                AppendShilpiLog($"Push failed for {row.SnapshotId}: {ex.Message}");
                _tabs.SelectedIndex = 2;
            }
        }

        private void AddOrUpdateAnchor()
        {
            if (_anchorStore == null)
            {
                MessageBox.Show(this, "Open a project first.", "Floor anchors", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            using (var dialog = new AnchorEditDialog())
            {
                if (dialog.ShowDialog(this) != DialogResult.OK)
                    return;

                _anchorStore.Set(new FloorAnchor
                {
                    Name = dialog.AnchorName,
                    Origin = new Point3D(dialog.X, dialog.Y, dialog.Z)
                });

                LoadAnchors();
            }
        }

        private void TestShilpiConnection()
        {
            string address = _shilpiAddressBox.Text.Trim();
            if (string.IsNullOrEmpty(address))
                return;

            _shilpiStatusLabel.Text = "Connecting...";
            _shilpiStatusLabel.ForeColor = System.Drawing.Color.DimGray;
            Application.DoEvents();

            try
            {
                using (ShilpiDbClient.Connect(address))
                {
                    _shilpiStatusLabel.Text = $"Connected to {address}";
                    _shilpiStatusLabel.ForeColor = System.Drawing.Color.DarkGreen;
                    AppendShilpiLog($"Connected to {address}.");
                }
            }
            catch (ShilpiDbException ex)
            {
                _shilpiStatusLabel.Text = "Unreachable";
                _shilpiStatusLabel.ForeColor = System.Drawing.Color.DarkRed;
                AppendShilpiLog($"Connection to {address} failed: {ex.Message}");
            }
        }

        private void AppendShilpiLog(string line)
        {
            _shilpiLog.AppendText($"[{DateTime.Now:HH:mm:ss}] {line}{Environment.NewLine}");
        }

        /// <summary>Flat, grid-friendly view of a SnapshotManifest.</summary>
        public class SnapshotRow
        {
            public SnapshotManifest Manifest { get; }

            public SnapshotRow(SnapshotManifest manifest)
            {
                Manifest = manifest;
            }

            public string SnapshotId => Manifest.SnapshotId;
            public string Name => Manifest.Name;
            public string CreatedDisplay => Manifest.CreatedAt.ToString("dd MMM yyyy HH:mm");
            public int EntityCount => Manifest.Selection.EntityCount;

            public string ExtentDisplay
            {
                get
                {
                    var e = Manifest.Extent;
                    if (e?.Min == null || e.Max == null)
                        return "";
                    return $"({e.Min[0]:F1}, {e.Min[1]:F1}) - ({e.Max[0]:F1}, {e.Max[1]:F1})";
                }
            }

            public string AnchorDisplay => Manifest.FloorAnchor?.Name ?? "";
        }

        public class AnchorRow
        {
            private readonly FloorAnchor _anchor;

            public AnchorRow(FloorAnchor anchor)
            {
                _anchor = anchor;
            }

            public string Name => _anchor.Name;
            public double X => _anchor.Origin.X;
            public double Y => _anchor.Origin.Y;
            public double Z => _anchor.Origin.Z;
        }
    }
}
