param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'ChineseFilenameTool.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.CSharp

$source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using Microsoft.VisualBasic;
using Microsoft.Win32;

namespace ChineseFilenameTool
{
    internal sealed class Phrase
    {
        public readonly string Simplified;
        public readonly string Traditional;

        public Phrase(string simplified, string traditional)
        {
            Simplified = simplified;
            Traditional = traditional;
        }
    }

    internal sealed class ConversionResult
    {
        public readonly List<string> Renamed = new List<string>();
        public readonly List<string> Skipped = new List<string>();
        public readonly List<string> Errors = new List<string>();
    }

    internal static class Converter
    {
        private static readonly Phrase[] Phrases = new Phrase[]
        {
            new Phrase("软件", "軟體"),
            new Phrase("文件夹", "資料夾"),
            new Phrase("文件", "檔案"),
            new Phrase("网络", "網路"),
            new Phrase("视频", "影片"),
            new Phrase("服务器", "伺服器"),
            new Phrase("数据库", "資料庫"),
            new Phrase("程序", "程式"),
            new Phrase("打印机", "印表機"),
            new Phrase("鼠标", "滑鼠"),
            new Phrase("硬盘", "硬碟"),
            new Phrase("屏幕", "螢幕"),
            new Phrase("账户", "帳戶"),
            new Phrase("账号", "帳號"),
            new Phrase("信息", "資訊")
        };

        public static string ConvertText(string text, bool toTraditional)
        {
            IEnumerable<Phrase> phrases = Phrases.OrderByDescending(p => p.Simplified.Length);
            if (toTraditional)
            {
                foreach (Phrase phrase in phrases)
                {
                    text = text.Replace(phrase.Simplified, phrase.Traditional);
                }
                return Strings.StrConv(text, VbStrConv.TraditionalChinese, 2052);
            }

            foreach (Phrase phrase in phrases.OrderByDescending(p => p.Traditional.Length))
            {
                text = text.Replace(phrase.Traditional, phrase.Simplified);
            }
            return Strings.StrConv(text, VbStrConv.SimplifiedChinese, 2052);
        }

        public static ConversionResult Rename(string[] paths, bool toTraditional)
        {
            ConversionResult result = new ConversionResult();
            foreach (string inputPath in paths)
            {
                try
                {
                    if (String.IsNullOrWhiteSpace(inputPath))
                    {
                        continue;
                    }

                    string fullPath = Path.GetFullPath(inputPath);
                    bool isDirectory = Directory.Exists(fullPath);
                    bool isFile = File.Exists(fullPath);
                    if (!isDirectory && !isFile)
                    {
                        result.Errors.Add(inputPath + " : path does not exist");
                        continue;
                    }

                    string parent;
                    string name;
                    if (isDirectory)
                    {
                        DirectoryInfo info = new DirectoryInfo(fullPath);
                        if (info.Parent == null)
                        {
                            result.Errors.Add(fullPath + " : cannot rename a filesystem root");
                            continue;
                        }
                        parent = info.Parent.FullName;
                        name = info.Name;
                    }
                    else
                    {
                        FileInfo info = new FileInfo(fullPath);
                        parent = info.DirectoryName;
                        name = info.Name;
                    }

                    string extension = isDirectory ? String.Empty : Path.GetExtension(name);
                    string baseName = extension.Length == 0
                        ? name
                        : name.Substring(0, name.Length - extension.Length);
                    string newName = ConvertText(baseName, toTraditional) + extension;

                    if (newName == name)
                    {
                        result.Skipped.Add("No change: " + name);
                        continue;
                    }

                    string targetPath = Path.Combine(parent, newName);
                    if (File.Exists(targetPath) || Directory.Exists(targetPath))
                    {
                        result.Errors.Add(name + " : target already exists");
                        continue;
                    }

                    if (isDirectory)
                    {
                        Directory.Move(fullPath, targetPath);
                    }
                    else
                    {
                        File.Move(fullPath, targetPath);
                    }
                    result.Renamed.Add(name + " -> " + newName);
                }
                catch (Exception ex)
                {
                    result.Errors.Add(inputPath + " : " + ex.Message);
                }
            }
            return result;
        }

        public static ConversionResult RenameFolder(string folderPath, bool toTraditional, bool recursive)
        {
            ConversionResult result = new ConversionResult();
            try
            {
                if (String.IsNullOrWhiteSpace(folderPath) || !Directory.Exists(folderPath))
                {
                    result.Errors.Add("Invalid folder: " + folderPath);
                    return result;
                }

                SearchOption searchOpt = recursive ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly;

                // Collect all paths first (bottom-up for directories so renaming parents doesn't break child enumeration)
                var dirs = Directory.GetDirectories(folderPath, "*", searchOpt)
                    .OrderByDescending(d => d.Length)
                    .ToArray();
                var files = Directory.GetFiles(folderPath, "*", searchOpt);

                // Process directories first (bottom-up: deepest first)
                foreach (string dir in dirs)
                {
                    ProcessItem(dir, true, toTraditional, result);
                }

                // Then files
                foreach (string file in files)
                {
                    ProcessItem(file, false, toTraditional, result);
                }
            }
            catch (Exception ex)
            {
                result.Errors.Add(folderPath + " : " + ex.Message);
            }
            return result;
        }

        private static void ProcessItem(string fullPath, bool isDirectory, bool toTraditional, ConversionResult result)
        {
            try
            {
                string parent;
                string name;
                if (isDirectory)
                {
                    DirectoryInfo info = new DirectoryInfo(fullPath);
                    if (info.Parent == null) return;
                    parent = info.Parent.FullName;
                    name = info.Name;
                }
                else
                {
                    FileInfo info = new FileInfo(fullPath);
                    parent = info.DirectoryName;
                    name = info.Name;
                }

                string extension = isDirectory ? String.Empty : Path.GetExtension(name);
                string baseName = extension.Length == 0
                    ? name
                    : name.Substring(0, name.Length - extension.Length);
                string newName = ConvertText(baseName, toTraditional) + extension;

                if (newName == name)
                {
                    result.Skipped.Add("No change: " + name);
                    return;
                }

                string targetPath = Path.Combine(parent, newName);
                if (File.Exists(targetPath) || Directory.Exists(targetPath))
                {
                    result.Errors.Add(name + " : target already exists");
                    return;
                }

                if (isDirectory)
                {
                    Directory.Move(fullPath, targetPath);
                }
                else
                {
                    File.Move(fullPath, targetPath);
                }
                result.Renamed.Add(name + " -> " + newName);
            }
            catch (Exception ex)
            {
                result.Errors.Add(fullPath + " : " + ex.Message);
            }
        }
    }

    internal static class ToolRegistry
    {
        private static readonly string[] FileRoots = new string[]
        {
            "Software\\Classes\\*",
            "Software\\Classes\\Directory"
        };

        private static readonly string[] FolderBackgroundRoots = new string[]
        {
            "Software\\Classes\\Directory\\Background"
        };

        private const string TraditionalVerb = "ChineseFilenameTool.ToTraditional";
        private const string SimplifiedVerb = "ChineseFilenameTool.ToSimplified";
        private const string TraditionalFolderVerb = "ChineseFilenameTool.ToTraditionalFolder";
        private const string SimplifiedFolderVerb = "ChineseFilenameTool.ToSimplifiedFolder";

        public static void Install(string executablePath)
        {
            RemoveLegacyEntries();
            // File/folder context menu (multi-select)
            InstallVerb(TraditionalVerb, "轉換檔名為繁體中文", "--to-traditional", executablePath, FileRoots);
            InstallVerb(SimplifiedVerb, "轉換檔名為簡體中文", "--to-simplified", executablePath, FileRoots);
            // Folder background context menu (right-click empty space in folder)
            InstallVerb(TraditionalFolderVerb, "轉換此資料夾內所有檔名為繁體中文", "--to-traditional --folder", executablePath, FolderBackgroundRoots);
            InstallVerb(SimplifiedFolderVerb, "轉換此資料夾內所有檔名為簡體中文", "--to-simplified --folder", executablePath, FolderBackgroundRoots);
        }

        private static void InstallVerb(string verb, string label, string direction, string executablePath, string[] roots)
        {
            string command = "\"" + executablePath + "\" " + direction + " --quiet \"%V\"";
            foreach (string root in roots)
            {
                using (RegistryKey menu = Registry.CurrentUser.CreateSubKey(root + "\\shell\\" + verb))
                {
                    menu.SetValue("", label, RegistryValueKind.String);
                    menu.SetValue("MultiSelectModel", "Document", RegistryValueKind.String);
                    using (RegistryKey commandKey = menu.CreateSubKey("command"))
                    {
                        commandKey.SetValue("", command, RegistryValueKind.String);
                    }
                }
            }
        }

        public static void Uninstall()
        {
            foreach (string root in FileRoots)
            {
                DeleteIfPresent(root + "\\shell\\" + TraditionalVerb);
                DeleteIfPresent(root + "\\shell\\" + SimplifiedVerb);
            }
            foreach (string root in FolderBackgroundRoots)
            {
                DeleteIfPresent(root + "\\shell\\" + TraditionalFolderVerb);
                DeleteIfPresent(root + "\\shell\\" + SimplifiedFolderVerb);
            }
            RemoveLegacyEntries();
        }

        private static void RemoveLegacyEntries()
        {
            foreach (string root in FileRoots)
            {
                DeleteIfPresent(root + "\\shell\\ConvertChinese.ToTraditional");
                DeleteIfPresent(root + "\\shell\\ConvertChinese.ToSimplified");
            }
        }

        private static void DeleteIfPresent(string path)
        {
            try
            {
                Registry.CurrentUser.DeleteSubKeyTree(path, false);
            }
            catch (ArgumentException)
            {
            }
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly Label statusLabel;

        public MainForm()
        {
            Text = "繁簡檔名轉換工具";
            ClientSize = new Size(460, 220);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;

            Label description = new Label();
            description.AutoSize = true;
            description.Location = new Point(30, 25);
            description.Text = "安裝後，在檔案或資料夾按右鍵即可使用。也可在資料夾空白處按右鍵轉換整夾內檔名。";

            Button installButton = new Button();
            installButton.Text = "安裝這個工具";
            installButton.Location = new Point(30, 75);
            installButton.Size = new Size(180, 42);
            installButton.Click += InstallButton_Click;

            Button uninstallButton = new Button();
            uninstallButton.Text = "刪除這個工具";
            uninstallButton.Location = new Point(230, 75);
            uninstallButton.Size = new Size(180, 42);
            uninstallButton.Click += UninstallButton_Click;

            statusLabel = new Label();
            statusLabel.AutoSize = true;
            statusLabel.Location = new Point(30, 145);
            statusLabel.Text = "狀態：尚未操作";

            Controls.Add(description);
            Controls.Add(installButton);
            Controls.Add(uninstallButton);
            Controls.Add(statusLabel);
        }

        private void InstallButton_Click(object sender, EventArgs e)
        {
            try
            {
                ToolRegistry.Install(Application.ExecutablePath);
                statusLabel.Text = "狀態：安裝完成";
                MessageBox.Show("右鍵選單已安裝。", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void UninstallButton_Click(object sender, EventArgs e)
        {
            try
            {
                ToolRegistry.Uninstall();
                statusLabel.Text = "狀態：已刪除右鍵選單";
                MessageBox.Show("右鍵選單已刪除。\r\n\r\nEXE 檔案請手動刪除。", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }

    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            if (args.Length > 0 && args[0].Equals("--install", StringComparison.OrdinalIgnoreCase))
            {
                ToolRegistry.Install(Application.ExecutablePath);
                return 0;
            }
            if (args.Length > 0 && args[0].Equals("--uninstall", StringComparison.OrdinalIgnoreCase))
            {
                ToolRegistry.Uninstall();
                return 0;
            }

            if (args.Length == 0 || args[0].Equals("--ui", StringComparison.OrdinalIgnoreCase))
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm());
                return 0;
            }

            bool toTraditional = args.Any(a => a.Equals("--to-traditional", StringComparison.OrdinalIgnoreCase));
            bool toSimplified = args.Any(a => a.Equals("--to-simplified", StringComparison.OrdinalIgnoreCase));
            if (!toTraditional && !toSimplified)
            {
                return 2;
            }

            bool isFolderMode = args.Any(a => a.Equals("--folder", StringComparison.OrdinalIgnoreCase));
            bool quiet = args.Any(a => a.Equals("--quiet", StringComparison.OrdinalIgnoreCase));

            string[] paths = args.Skip(1)
                .Where(a => !a.Equals("--quiet", StringComparison.OrdinalIgnoreCase))
                .Where(a => !a.Equals("--folder", StringComparison.OrdinalIgnoreCase))
                .Where(a => !a.Equals("--to-traditional", StringComparison.OrdinalIgnoreCase))
                .Where(a => !a.Equals("--to-simplified", StringComparison.OrdinalIgnoreCase))
                .Where(a => !a.Equals("%1", StringComparison.OrdinalIgnoreCase))
                .Where(a => !a.Equals("%*", StringComparison.OrdinalIgnoreCase))
                .Where(a => !a.Equals("%V", StringComparison.OrdinalIgnoreCase))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();

            if (paths.Length == 0)
            {
                return 2;
            }

            ConversionResult result;
            if (isFolderMode)
            {
                string folder = paths[0];
                bool recursive = false;
                if (!quiet)
                {
                    DialogResult dr = MessageBox.Show(
                        "是否包含子資料夾一佝轉換？\n\n是(是) = 適用到所有子層类\n否(否) = 只轉換此層类目錄檔名和子資料夾",
                        "轉換檄影範圍",
                        MessageBoxButtons.YesNo,
                        MessageBoxIcon.Question);
                    recursive = (dr == DialogResult.Yes);
                }
                result = Converter.RenameFolder(folder, toTraditional, recursive);
            }
            else
            {
                result = Converter.Rename(paths, toTraditional);
            }

            if (quiet)
            {
                if (result.Errors.Count > 0)
                {
                    string logPath = Path.Combine(Path.GetTempPath(), "ChineseFilenameTool.log");
                    File.AppendAllText(logPath, DateTime.Now.ToString("s") + Environment.NewLine + String.Join(Environment.NewLine, result.Errors) + Environment.NewLine, Encoding.UTF8);
                }
                return result.Errors.Count == 0 ? 0 : 1;
            }

            List<string> lines = new List<string>();
            lines.Add("已重新命名：" + result.Renamed.Count);
            lines.Add("無需變更：" + result.Skipped.Count);
            lines.Add("錯誤：" + result.Errors.Count);
            if (result.Renamed.Count > 0)
            {
                lines.Add(String.Empty);
                lines.AddRange(result.Renamed);
            }
            if (result.Errors.Count > 0)
            {
                lines.Add(String.Empty);
                lines.AddRange(result.Errors);
            }
            MessageBox.Show(String.Join(Environment.NewLine, lines), "檔名轉換", MessageBoxButtons.OK, result.Errors.Count > 0 ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
            return result.Errors.Count == 0 ? 0 : 1;
        }
    }
}
'@

$compiler = New-Object Microsoft.CSharp.CSharpCodeProvider
$parameters = New-Object System.CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable = $true
$parameters.OutputAssembly = [System.IO.Path]::GetFullPath($OutputPath)
$parameters.CompilerOptions = '/target:winexe /platform:anycpu /optimize+'
$parameters.ReferencedAssemblies.Add('System.dll') | Out-Null
$parameters.ReferencedAssemblies.Add('System.Core.dll') | Out-Null
$parameters.ReferencedAssemblies.Add('System.Drawing.dll') | Out-Null
$parameters.ReferencedAssemblies.Add('System.Windows.Forms.dll') | Out-Null
$parameters.ReferencedAssemblies.Add('Microsoft.VisualBasic.dll') | Out-Null

$result = $compiler.CompileAssemblyFromSource($parameters, $source)
if ($result.Errors.HasErrors) {
    foreach ($error in $result.Errors) {
        Write-Error $error.ToString()
    }
    exit 1
}

Write-Host "Built: $($parameters.OutputAssembly)"