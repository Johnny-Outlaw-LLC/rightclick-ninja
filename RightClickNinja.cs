using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace RightClickNinja
{
    static class Program
    {
        const string MutexName = "Local\\RightClickNinja";
        const string EventName = "Local\\RightClickNinjaPulse";

        internal static string QueuePath
        {
            get { return Path.Combine(Path.GetTempPath(), "rightclick-ninja-queue.txt"); }
        }

        [STAThread]
        static void Main(string[] args)
        {
            Enqueue(args);

            bool createdNew;
            using (var mutex = new Mutex(true, MutexName, out createdNew))
            {
                if (!createdNew)
                {
                    try
                    {
                        using (var existing = EventWaitHandle.OpenExisting(EventName))
                            existing.Set();
                    }
                    catch { }
                    return;
                }

                using (var pulse = new EventWaitHandle(false, EventResetMode.AutoReset, EventName))
                {
                    Application.EnableVisualStyles();
                    Application.SetCompatibleTextRenderingDefault(false);

                    // Explorer often starts one process per file; wait briefly to collect them.
                    var until = DateTime.UtcNow.AddMilliseconds(900);
                    while (DateTime.UtcNow < until)
                        pulse.WaitOne(50);

                    var form = new MainForm(Drain().ToArray());
                    var timer = new System.Windows.Forms.Timer { Interval = 200 };
                    timer.Tick += delegate
                    {
                        if (pulse.WaitOne(0)) { /* woke */ }
                        var more = Drain();
                        if (more.Count > 0) form.ImportPaths(more);
                    };
                    timer.Start();
                    form.FormClosed += delegate { timer.Stop(); };
                    Application.Run(form);
                }
            }
        }

        static void Enqueue(string[] args)
        {
            if (args == null || args.Length == 0) return;
            try
            {
                var lines = new List<string>();
                foreach (var a in args)
                {
                    if (!string.IsNullOrWhiteSpace(a))
                        lines.Add(a.Trim().Trim('"'));
                }
                if (lines.Count == 0) return;
                File.AppendAllLines(QueuePath, lines, Encoding.UTF8);
            }
            catch { }
        }

        static List<string> Drain()
        {
            var result = new List<string>();
            try
            {
                if (!File.Exists(QueuePath)) return result;
                string[] lines;
                using (var fs = new FileStream(QueuePath, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                using (var sr = new StreamReader(fs, Encoding.UTF8))
                {
                    lines = sr.ReadToEnd().Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    fs.SetLength(0);
                }
                foreach (var line in lines)
                {
                    var p = line.Trim().Trim('"');
                    if (p.Length > 0) result.Add(p);
                }
            }
            catch { }
            return result;
        }
    }

    public class MainForm : Form
    {
        readonly List<string> files = new List<string>();
        readonly ListView list;
        readonly NumericUpDown numDays, numHours, numMins;
        readonly CheckBox chkCreated, chkModified, chkAccessed, chkEmbedded;
        readonly Label status, lblCount;
        readonly string exiftoolPath;
        readonly string appDir;

        public MainForm(string[] args)
        {
            appDir = AppDomain.CurrentDomain.BaseDirectory;
            exiftoolPath = Path.Combine(appDir, "exiftool.exe");
            if (!File.Exists(exiftoolPath))
                exiftoolPath = Path.Combine(appDir, "..", "bin", "exiftool.exe");
            exiftoolPath = Path.GetFullPath(exiftoolPath);

            Text = "Right Click Ninja";
            Size = new Size(980, 580);
            MinimumSize = new Size(800, 480);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9f);
            AllowDrop = true;
            DragEnter += OnDragEnter;
            DragDrop += OnDragDrop;

            var btnSelect = new Button { Text = "Select files...", Location = new Point(12, 12), Size = new Size(110, 28) };
            btnSelect.Click += (s, e) => PickFiles();
            var btnClear = new Button { Text = "Clear", Location = new Point(128, 12), Size = new Size(70, 28) };
            btnClear.Click += (s, e) => { files.Clear(); RefreshList(); status.Text = "Cleared."; };
            lblCount = new Label { Text = "0 files - drag files here", Location = new Point(210, 17), AutoSize = true };

            list = new ListView
            {
                View = View.Details,
                FullRowSelect = true,
                GridLines = true,
                AllowDrop = true,
                Location = new Point(12, 48),
                Size = new Size(820, 300),
                Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right
            };
            list.Columns.Add("File", 160);
            list.Columns.Add("Explorer Date", 130);
            list.Columns.Add("Explorer (new)", 130);
            list.Columns.Add("Created", 115);
            list.Columns.Add("Created (new)", 115);
            list.Columns.Add("Modified", 115);
            list.Columns.Add("Modified (new)", 115);
            list.DragEnter += OnDragEnter;
            list.DragDrop += OnDragDrop;

            var grp = new GroupBox
            {
                Text = "Offset (negative = earlier)",
                Location = new Point(12, 360),
                Size = new Size(420, 70),
                Anchor = AnchorStyles.Bottom | AnchorStyles.Left
            };
            numDays = MakeNum(grp, "Days", 16, 0);
            numHours = MakeNum(grp, "Hours", 150, 0);
            numMins = MakeNum(grp, "Mins", 290, 0);
            EventHandler onChange = (s, e) => RefreshList();
            numDays.ValueChanged += onChange;
            numHours.ValueChanged += onChange;
            numMins.ValueChanged += onChange;

            var grpStamp = new GroupBox
            {
                Text = "Change",
                Location = new Point(444, 360),
                Size = new Size(388, 70),
                Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right
            };
            chkCreated = new CheckBox { Text = "Date created", Checked = true, Location = new Point(12, 22), AutoSize = true };
            chkModified = new CheckBox { Text = "Date modified", Checked = true, Location = new Point(12, 42), AutoSize = true };
            chkAccessed = new CheckBox { Text = "Date accessed", Checked = false, Location = new Point(140, 22), AutoSize = true };
            chkEmbedded = new CheckBox
            {
                Text = "Embedded media dates (Explorer Date / Date taken)",
                Checked = true,
                Location = new Point(140, 42),
                AutoSize = true
            };
            chkCreated.CheckedChanged += onChange;
            chkModified.CheckedChanged += onChange;
            chkAccessed.CheckedChanged += onChange;
            chkEmbedded.CheckedChanged += onChange;
            grpStamp.Controls.AddRange(new Control[] { chkCreated, chkModified, chkAccessed, chkEmbedded });

            var btnApply = new Button
            {
                Text = "Apply offset",
                Location = new Point(12, 445),
                Size = new Size(120, 32),
                Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
                BackColor = Color.FromArgb(255, 107, 53),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat
            };
            btnApply.Click += (s, e) => ApplyOffset();

            status = new Label
            {
                Text = "Explorer Date for photos/video is often embedded Date taken, not Created. Check that box.",
                Location = new Point(148, 452),
                AutoSize = true,
                Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
                MaximumSize = new Size(680, 40)
            };

            Controls.AddRange(new Control[] {
                btnSelect, btnClear, lblCount, list, grp, grpStamp, btnApply, status
            });

            if (args != null && args.Length > 0)
                AddPaths(args);
        }

        static NumericUpDown MakeNum(GroupBox grp, string label, int x, decimal val)
        {
            var l = new Label { Text = label, Location = new Point(x, 28), AutoSize = true };
            var n = new NumericUpDown
            {
                Location = new Point(x + 42, 24),
                Size = new Size(70, 24),
                Minimum = -99999,
                Maximum = 99999,
                Value = val
            };
            grp.Controls.Add(l);
            grp.Controls.Add(n);
            return n;
        }

        TimeSpan GetOffset()
        {
            return TimeSpan.FromDays((double)numDays.Value)
                 + TimeSpan.FromHours((double)numHours.Value)
                 + TimeSpan.FromMinutes((double)numMins.Value);
        }

        string FormatOffset(TimeSpan ts)
        {
            string sign = ts.Ticks >= 0 ? "+" : "";
            return sign + ts.Days + "d " + ts.Hours + "h " + ts.Minutes + "m";
        }

        // ExifTool shift body for += : "0:0:D H:M:0" or "-0:0:D H:M:0" (no leading +)
        string GetExifShift()
        {
            var ts = GetOffset();
            bool neg = ts.Ticks < 0;
            if (neg) ts = ts.Negate();
            string body = string.Format("0:0:{0} {1}:{2}:0", ts.Days, ts.Hours, ts.Minutes);
            return (neg ? "-" : "") + body;
        }

        void OnDragEnter(object sender, DragEventArgs e)
        {
            e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop)
                ? DragDropEffects.Copy
                : DragDropEffects.None;
        }

        void OnDragDrop(object sender, DragEventArgs e)
        {
            var paths = e.Data.GetData(DataFormats.FileDrop) as string[];
            if (paths != null) AddPaths(paths);
        }

        void PickFiles()
        {
            using (var dlg = new OpenFileDialog { Multiselect = true, Title = "Select files to offset", Filter = "All files (*.*)|*.*" })
            {
                if (dlg.ShowDialog(this) == DialogResult.OK)
                    AddPaths(dlg.FileNames);
            }
        }

        public void ImportPaths(IEnumerable<string> paths)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => ImportPaths(paths)));
                return;
            }
            AddPaths(paths);
        }

        void AddPaths(IEnumerable<string> paths)
        {
            int added = 0;
            foreach (var p in paths)
            {
                if (string.IsNullOrWhiteSpace(p)) continue;
                if (Directory.Exists(p))
                {
                    foreach (var f in Directory.EnumerateFiles(p, "*", SearchOption.AllDirectories))
                    {
                        if (!files.Contains(f, StringComparer.OrdinalIgnoreCase))
                        {
                            files.Add(f);
                            added++;
                        }
                    }
                }
                else if (File.Exists(p))
                {
                    if (!files.Contains(p, StringComparer.OrdinalIgnoreCase))
                    {
                        files.Add(p);
                        added++;
                    }
                }
            }
            RefreshList();
            if (added > 0)
                status.Text = "Added " + added + ". Live preview updates as you change the offset.";
        }

        void RefreshList()
        {
            var offset = GetOffset();
            list.BeginUpdate();
            list.Items.Clear();
            foreach (var path in files)
            {
                try
                {
                    var fi = new FileInfo(path);
                    var explorer = GetExplorerDate(path);
                    var created = fi.CreationTime;
                    var modified = fi.LastWriteTime;
                    var row = new ListViewItem(fi.Name);
                    row.SubItems.Add(explorer.Display);
                    row.SubItems.Add(PreviewCell(chkEmbedded.Checked, explorer.Value, offset, explorer.Kind));
                    row.SubItems.Add(created.ToString("yyyy-MM-dd HH:mm"));
                    row.SubItems.Add(PreviewCell(chkCreated.Checked, created, offset, null));
                    row.SubItems.Add(modified.ToString("yyyy-MM-dd HH:mm"));
                    row.SubItems.Add(PreviewCell(chkModified.Checked, modified, offset, null));
                    list.Items.Add(row);
                }
                catch (Exception ex)
                {
                    var row = new ListViewItem(Path.GetFileName(path));
                    row.SubItems.Add("ERROR");
                    row.SubItems.Add(ex.Message);
                    row.SubItems.Add("");
                    row.SubItems.Add("");
                    row.SubItems.Add("");
                    row.SubItems.Add("");
                    list.Items.Add(row);
                }
            }
            list.EndUpdate();
            lblCount.Text = files.Count + " file" + (files.Count == 1 ? "" : "s") + " - drag more here";
            if (files.Count > 0)
            {
                var parts = new List<string>();
                if (chkEmbedded.Checked) parts.Add("Explorer");
                if (chkCreated.Checked) parts.Add("Created");
                if (chkModified.Checked) parts.Add("Modified");
                if (chkAccessed.Checked) parts.Add("Accessed");
                status.Text = files.Count + " files - live preview " + FormatOffset(offset)
                    + (parts.Count > 0 ? " -> " + string.Join(", ", parts) : " (nothing checked)");
            }
        }

        static string PreviewCell(bool enabled, DateTime? current, TimeSpan offset, string kind)
        {
            if (!enabled) return "";
            if (!current.HasValue) return "(no date)";
            string s = (current.Value + offset).ToString("yyyy-MM-dd HH:mm");
            if (!string.IsNullOrEmpty(kind)) s += " (" + kind + ")";
            return s;
        }

        static string PreviewCell(bool enabled, DateTime current, TimeSpan offset, string kind)
        {
            return PreviewCell(enabled, (DateTime?)current, offset, kind);
        }

        // What Explorer's Date column usually shows for camera files
        ExplorerDateInfo GetExplorerDate(string path)
        {
            try
            {
                var shellType = Type.GetTypeFromProgID("Shell.Application");
                dynamic shell = Activator.CreateInstance(shellType);
                string dir = Path.GetDirectoryName(path);
                string name = Path.GetFileName(path);
                dynamic folder = shell.NameSpace(dir);
                dynamic item = folder.ParseName(name);
                if (item == null) return ExplorerDateInfo.Empty;

                string[] prefer = { "Date taken", "Media created", "Content created", "Date" };
                for (int i = 0; i < 320; i++)
                {
                    string hdr = folder.GetDetailsOf(null, i) as string;
                    if (string.IsNullOrEmpty(hdr)) continue;
                    foreach (var p in prefer)
                    {
                        if (string.Equals(hdr, p, StringComparison.OrdinalIgnoreCase))
                        {
                            string val = folder.GetDetailsOf(item, i) as string;
                            if (string.IsNullOrWhiteSpace(val)) continue;
                            string clean = CleanShellDate(val);
                            DateTime dt;
                            DateTime? parsed = DateTime.TryParse(clean, out dt) ? (DateTime?)dt : null;
                            return new ExplorerDateInfo
                            {
                                Display = clean + " (" + hdr + ")",
                                Value = parsed,
                                Kind = hdr
                            };
                        }
                    }
                }
            }
            catch { }
            return ExplorerDateInfo.Empty;
        }

        struct ExplorerDateInfo
        {
            public string Display;
            public DateTime? Value;
            public string Kind;
            public static ExplorerDateInfo Empty
            {
                get
                {
                    return new ExplorerDateInfo { Display = "(none)", Value = null, Kind = null };
                }
            }
        }

        static string CleanShellDate(string s)
        {
            if (string.IsNullOrEmpty(s)) return s;
            var sb = new StringBuilder(s.Length);
            foreach (char c in s)
            {
                if (c == 8206 || c == 8207) continue; // LTR/RTL marks Explorer injects
                sb.Append(c);
            }
            return sb.ToString().Trim();
        }

        void ApplyOffset()
        {
            if (files.Count == 0)
            {
                MessageBox.Show(this, "Select or drag files first.", Text);
                return;
            }
            if (!chkCreated.Checked && !chkModified.Checked && !chkAccessed.Checked && !chkEmbedded.Checked)
            {
                MessageBox.Show(this, "Pick at least one timestamp to change.", Text);
                return;
            }
            var offset = GetOffset();
            if (offset.Ticks == 0)
            {
                MessageBox.Show(this, "Offset is zero - nothing to do.", Text);
                return;
            }
            if (chkEmbedded.Checked && !File.Exists(exiftoolPath))
            {
                MessageBox.Show(this,
                    "Embedded media dates need exiftool.exe next to this app.\nExpected:\n" + exiftoolPath,
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            var msg = "Shift " + files.Count + " file(s) by " + offset + "?";
            if (chkEmbedded.Checked)
                msg += "\n\nEmbedded Date taken / Media created will also shift (this is what Explorer Date shows for DJI photos/video).";
            if (MessageBox.Show(this, msg, "Apply offset", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;

            int ok = 0, fail = 0;
            Cursor = Cursors.WaitCursor;
            try
            {
                if (chkEmbedded.Checked)
                {
                    if (!RunExifShift(files, GetExifShift()))
                        MessageBox.Show(this, "ExifTool reported a problem. Filesystem stamps may still be applied.", Text);
                }

                foreach (var path in files.ToArray())
                {
                    try
                    {
                        var fi = new FileInfo(path);
                        if (chkCreated.Checked) fi.CreationTime = fi.CreationTime + offset;
                        if (chkModified.Checked) fi.LastWriteTime = fi.LastWriteTime + offset;
                        if (chkAccessed.Checked) fi.LastAccessTime = fi.LastAccessTime + offset;
                        ok++;
                    }
                    catch { fail++; }
                }
            }
            finally { Cursor = Cursors.Default; }

            RefreshList();
            status.Text = "Done: " + ok + " updated, " + fail + " failed. Refresh Explorer if Date looks stale.";
            if (fail > 0)
                MessageBox.Show(this, ok + " updated, " + fail + " failed (permissions or locked files).", Text);
        }

        bool RunExifShift(List<string> paths, string shift)
        {
            // Batch via argfile to avoid command-line length limits
            string argFile = Path.Combine(Path.GetTempPath(), "fdo-files-" + Guid.NewGuid().ToString("N") + ".txt");
            try
            {
                File.WriteAllLines(argFile, paths, Encoding.UTF8);
                var psi = new ProcessStartInfo
                {
                    FileName = exiftoolPath,
                    // -P keeps filesystem times; we shift those ourselves below.
                    // AllDates covers stills; Media/Track tags are required for MP4/MOV Explorer Date.
                    Arguments = "-overwrite_original -P "
                        + "\"-AllDates+=" + shift + "\" "
                        + "\"-MediaCreateDate+=" + shift + "\" "
                        + "\"-MediaModifyDate+=" + shift + "\" "
                        + "\"-TrackCreateDate+=" + shift + "\" "
                        + "\"-TrackModifyDate+=" + shift + "\" "
                        + "-charset filename=utf8 -@ \"" + argFile + "\"",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    WorkingDirectory = Path.GetDirectoryName(exiftoolPath)
                };
                using (var p = Process.Start(psi))
                {
                    string stdout = p.StandardOutput.ReadToEnd();
                    string stderr = p.StandardError.ReadToEnd();
                    p.WaitForExit(600000);
                    if (p.ExitCode > 1) // 0=ok, 1=warnings, 2+=error
                    {
                        MessageBox.Show(this, "ExifTool:\n" + (stderr + "\n" + stdout).Trim(), Text);
                        return false;
                    }
                }
                return true;
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "ExifTool failed: " + ex.Message, Text);
                return false;
            }
            finally
            {
                try { File.Delete(argFile); } catch { }
            }
        }

        void InstallContextMenu()
        {
            try
            {
                string exe = Application.ExecutablePath;
                string[] roots = {
                    @"Software\Classes\*\shell\OutlawUpdateDates",
                    @"Software\Classes\AllFilesystemObjects\shell\OutlawUpdateDates",
                    @"Software\Classes\Directory\shell\OutlawUpdateDates"
                };
                foreach (var root in roots)
                {
                    using (var key = Registry.CurrentUser.CreateSubKey(root))
                    {
                        key.SetValue("", "Right Click Ninja");
                        key.SetValue("Icon", exe);
                        key.SetValue("MultiSelectModel", "Player");
                        key.SetValue("Position", "Top");
                    }
                    using (var key = Registry.CurrentUser.CreateSubKey(root + @"\command"))
                    {
                        key.SetValue("", "\"" + exe + "\" \"%1\"");
                    }
                }
                MessageBox.Show(this,
                    "Right-click menu installed.\n\nShow more options -> Right Click Ninja",
                    Text);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Could not install menu: " + ex.Message, Text);
            }
        }
    }
}
