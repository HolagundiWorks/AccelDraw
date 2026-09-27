using System;
using System.Windows.Forms;

namespace AccelDraw.Manager
{
    /// <summary>Small modal for defining/updating one floor anchor by typed coordinates.</summary>
    public class AnchorEditDialog : Form
    {
        private readonly TextBox _nameBox;
        private readonly TextBox _xBox;
        private readonly TextBox _yBox;
        private readonly TextBox _zBox;

        public string AnchorName => _nameBox.Text.Trim();
        public double X => ParseOrZero(_xBox.Text);
        public double Y => ParseOrZero(_yBox.Text);
        public double Z => ParseOrZero(_zBox.Text);

        public AnchorEditDialog()
        {
            Text = "Floor Anchor";
            Width = 340;
            Height = 230;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterParent;
            MaximizeBox = false;
            MinimizeBox = false;

            var nameLabel = new Label { Text = "Name:", Left = 12, Top = 16, Width = 80 };
            _nameBox = new TextBox { Left = 100, Top = 12, Width = 200 };

            var xLabel = new Label { Text = "Origin X:", Left = 12, Top = 48, Width = 80 };
            _xBox = new TextBox { Left = 100, Top = 44, Width = 200, Text = "0" };

            var yLabel = new Label { Text = "Origin Y:", Left = 12, Top = 80, Width = 80 };
            _yBox = new TextBox { Left = 100, Top = 76, Width = 200, Text = "0" };

            var zLabel = new Label { Text = "Origin Z:", Left = 12, Top = 112, Width = 80 };
            _zBox = new TextBox { Left = 100, Top = 108, Width = 200, Text = "0" };

            var okButton = new Button { Text = "OK", Left = 130, Top = 150, Width = 80, DialogResult = DialogResult.OK };
            okButton.Click += (s, e) =>
            {
                if (string.IsNullOrWhiteSpace(AnchorName))
                {
                    MessageBox.Show(this, "Enter a name.", "Floor Anchor", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    DialogResult = DialogResult.None;
                }
            };
            var cancelButton = new Button { Text = "Cancel", Left = 220, Top = 150, Width = 80, DialogResult = DialogResult.Cancel };

            Controls.Add(nameLabel);
            Controls.Add(_nameBox);
            Controls.Add(xLabel);
            Controls.Add(_xBox);
            Controls.Add(yLabel);
            Controls.Add(_yBox);
            Controls.Add(zLabel);
            Controls.Add(_zBox);
            Controls.Add(okButton);
            Controls.Add(cancelButton);

            AcceptButton = okButton;
            CancelButton = cancelButton;
        }

        private static double ParseOrZero(string text) => double.TryParse(text, out var value) ? value : 0;
    }
}
