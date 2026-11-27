param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ToTraditional', 'ToSimplified')]
    [string]$Direction,

    [switch]$Quiet,

    [switch]$Folder,

    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'

function Show-Result {
    param(
        [string]$Message,
        [string]$Title,
        [System.Windows.Forms.MessageBoxIcon]$Icon
    )

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    ) | Out-Null
}

function Unescape-Unicode {
    param([string]$Value)
    return [System.Text.RegularExpressions.Regex]::Unescape($Value)
}

function Convert-ChineseText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    Add-Type -AssemblyName Microsoft.VisualBasic

    # Windows StrConv handles the basic character conversion. These phrase
    # replacements make common Taiwan-style filenames more natural.
    $toTraditionalPhrases = New-Object System.Collections.Specialized.OrderedDictionary
    $toTraditionalPhrases.Add((Unescape-Unicode '软件'), (Unescape-Unicode '軟體'))
    $toTraditionalPhrases.Add((Unescape-Unicode '文件'), (Unescape-Unicode '檔案'))
    $toTraditionalPhrases.Add((Unescape-Unicode '网络'), (Unescape-Unicode '網路'))
    $toTraditionalPhrases.Add((Unescape-Unicode '视频'), (Unescape-Unicode '影片'))
    $toTraditionalPhrases.Add((Unescape-Unicode '服务器'), (Unescape-Unicode '伺服器'))
    $toTraditionalPhrases.Add((Unescape-Unicode '数据库'), (Unescape-Unicode '資料庫'))
    $toTraditionalPhrases.Add((Unescape-Unicode '程序'), (Unescape-Unicode '程式'))
    $toTraditionalPhrases.Add((Unescape-Unicode '打印机'), (Unescape-Unicode '印表機'))
    $toTraditionalPhrases.Add((Unescape-Unicode '鼠标'), (Unescape-Unicode '滑鼠'))
    $toTraditionalPhrases.Add((Unescape-Unicode '硬盘'), (Unescape-Unicode '硬碟'))
    $toTraditionalPhrases.Add((Unescape-Unicode '屏幕'), (Unescape-Unicode '螢幕'))
    $toTraditionalPhrases.Add((Unescape-Unicode '账户'), (Unescape-Unicode '帳戶'))
    $toTraditionalPhrases.Add((Unescape-Unicode '账号'), (Unescape-Unicode '帳號'))
    $toTraditionalPhrases.Add((Unescape-Unicode '信息'), (Unescape-Unicode '資訊'))
    $toTraditionalPhrases.Add((Unescape-Unicode '文件夹'), (Unescape-Unicode '資料夾'))

    $toSimplifiedPhrases = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($pair in $toTraditionalPhrases.GetEnumerator()) {
        $toSimplifiedPhrases.Add($pair.Value, $pair.Key)
    }

    # LCID 2052 selects the Windows Chinese conversion table.
    if ($Mode -eq 'ToTraditional') {
        foreach ($pair in ($toTraditionalPhrases.GetEnumerator() | Sort-Object { $_.Key.Length } -Descending)) {
            $Text = $Text.Replace($pair.Key, $pair.Value)
        }

        return [Microsoft.VisualBasic.Strings]::StrConv(
            $Text,
            [Microsoft.VisualBasic.VbStrConv]::TraditionalChinese,
            2052
        )
    }

    foreach ($pair in ($toSimplifiedPhrases.GetEnumerator() | Sort-Object { $_.Key.Length } -Descending)) {
        $Text = $Text.Replace($pair.Key, $pair.Value)
    }

    return [Microsoft.VisualBasic.Strings]::StrConv(
        $Text,
        [Microsoft.VisualBasic.VbStrConv]::SimplifiedChinese,
        2052
    )
}

function Get-ParentDirectory {
    param([System.IO.FileSystemInfo]$Item)

    if ($Item.PSIsContainer) {
        if ($null -eq $Item.Parent) {
            return $null
        }
        return $Item.Parent.FullName
    }

    return $Item.DirectoryName
}

function Rename-SingleItem {
    param(
        [string]$FullPath,
        [bool]$IsDirectory,
        [string]$Direction,
        [ref]$Renamed,
        [ref]$Skipped,
        [ref]$Errors
    )

    try {
        $parent = if ($IsDirectory) {
            $info = Get-Item -LiteralPath $FullPath -Force
            if ($null -eq $info.Parent) { return }
            $info.Parent.FullName
        } else {
            $info = Get-Item -LiteralPath $FullPath -Force
            $info.DirectoryName
        }

        $name = (Get-Item -LiteralPath $FullPath -Force).Name
        $extension = if ($IsDirectory) { '' } else { [System.IO.Path]::GetExtension($name) }
        $baseName = if ($extension.Length -eq 0) { $name } else { $name.Substring(0, $name.Length - $extension.Length) }
        $newName = Convert-ChineseText -Text $baseName -Mode $Direction + $extension

        if ($newName -eq $name) {
            $Skipped.Value.Add("No change: $name")
            return
        }

        $targetPath = Join-Path -Path $parent -ChildPath $newName
        if (Test-Path -LiteralPath $targetPath) {
            $Errors.Value.Add("$name : target already exists")
            return
        }

        Rename-Item -LiteralPath $FullPath -NewName $newName -ErrorAction Stop
        $Renamed.Value.Add("$name -> $newName")
    }
    catch {
        $Errors.Value.Add("$FullPath : $($_.Exception.Message)")
    }
}

$renamed = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]

if ($Folder) {
    $folderPath = $Path[0]
    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
        $errors.Add("Invalid folder: $folderPath")
    }
    else {
        $recursive = $false
        if (-not $Quiet) {
            Add-Type -AssemblyName System.Windows.Forms
            $dr = [System.Windows.Forms.MessageBox]::Show(
                "是否包含子資料夾一併轉換？\n\n是 = 適用到所有子層級\n否 = 只轉換此層級目錄檔名和子資料夾",
                "轉換範圍",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            $recursive = ($dr -eq [System.Windows.Forms.DialogResult]::Yes)
        }

        $searchOpt = if ($recursive) { 'AllDirectories' } else { 'TopDirectoryOnly' }

        # Get directories bottom-up (deepest first) so renaming parents doesn't break child enumeration
        $dirs = Get-ChildItem -LiteralPath $folderPath -Directory -Recurse:$recursive | Sort-Object { $_.FullName.Length } -Descending
        foreach ($dir in $dirs) {
            Rename-SingleItem -FullPath $dir.FullName -IsDirectory $true -Direction $Direction -Renamed ([ref]$renamed) -Skipped ([ref]$skipped) -Errors ([ref]$errors)
        }

        # Then files
        $files = Get-ChildItem -LiteralPath $folderPath -File -Recurse:$recursive
        foreach ($file in $files) {
            Rename-SingleItem -FullPath $file.FullName -IsDirectory $false -Direction $Direction -Renamed ([ref]$renamed) -Skipped ([ref]$skipped) -Errors ([ref]$errors)
        }
    }
}
else {
    foreach ($inputPath in ($Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        try {
            $item = Get-Item -LiteralPath $inputPath -Force -ErrorAction Stop
            $isDir = $item.PSIsContainer
            Rename-SingleItem -FullPath $item.FullName -IsDirectory $isDir -Direction $Direction -Renamed ([ref]$renamed) -Skipped ([ref]$skipped) -Errors ([ref]$errors)
        }
        catch {
            $errors.Add("$inputPath : $($_.Exception.Message)")
        }
    }
}

if ($Quiet -and $errors.Count -eq 0) {
    exit 0
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Renamed: $($renamed.Count)")
$lines.Add("Skipped: $($skipped.Count)")
$lines.Add("Errors: $($errors.Count)")

if ($renamed.Count -gt 0) {
    $lines.Add('')
    $lines.AddRange($renamed)
}

if ($errors.Count -gt 0) {
    $lines.Add('')
    $lines.AddRange($errors)
}

Add-Type -AssemblyName System.Windows.Forms

$icon = if ($errors.Count -gt 0) {
    [System.Windows.Forms.MessageBoxIcon]::Warning
} else {
    [System.Windows.Forms.MessageBoxIcon]::Information
}

Show-Result -Message ($lines -join [Environment]::NewLine) -Title 'Chinese filename conversion' -Icon $icon