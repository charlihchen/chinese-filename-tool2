$ErrorActionPreference = 'Stop'

function U {
    param([string]$Value)
    return [System.Text.RegularExpressions.Regex]::Unescape($Value)
}

$tool = Join-Path $PSScriptRoot 'ChineseFilenameTool.exe'
$testDirectory = Join-Path $env:TEMP 'ChineseFilenameToolTest'

if (Test-Path -LiteralPath $testDirectory) {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
}

New-Item -Path $testDirectory -ItemType Directory -Force | Out-Null
$simplifiedFile = Join-Path $testDirectory (U '软件 文件.txt')
$traditionalFile = Join-Path $testDirectory (U '軟體 檔案.txt')
$simplifiedFolder = Join-Path $testDirectory (U '文件夹')
$traditionalFolder = Join-Path $testDirectory (U '資料夾')

New-Item -Path $simplifiedFile -ItemType File | Out-Null
New-Item -Path $simplifiedFolder -ItemType Directory | Out-Null

$process = Start-Process -FilePath $tool -ArgumentList @('--to-traditional', '--quiet', ('"' + $simplifiedFile + '"'), ('"' + $simplifiedFolder + '"')) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "EXE traditional conversion failed: $($process.ExitCode)" }
if (-not (Test-Path -LiteralPath (Join-Path $testDirectory (U '軟體 檔案.txt')))) { throw 'Traditional filename was not created.' }
if (-not (Test-Path -LiteralPath $traditionalFolder -PathType Container)) { throw 'Traditional folder was not created.' }

$process = Start-Process -FilePath $tool -ArgumentList @('--to-simplified', '--quiet', ('"' + $traditionalFile + '"')) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "EXE simplified conversion failed: $($process.ExitCode)" }
if (-not (Test-Path -LiteralPath (Join-Path $testDirectory (U '软件 文件.txt')))) { throw 'Simplified filename was not created.' }

# Test multi-file selection (simulated by passing multiple paths)
$multiTestDir = Join-Path $env:TEMP 'ChineseFilenameToolMultiTest'
if (Test-Path -LiteralPath $multiTestDir) { Remove-Item -LiteralPath $multiTestDir -Recurse -Force }
New-Item -Path $multiTestDir -ItemType Directory -Force | Out-Null
$multiFile1 = Join-Path $multiTestDir (U '软件1.txt')
$multiFile2 = Join-Path $multiTestDir (U '软件2.txt')
$multiFile3 = Join-Path $multiTestDir (U '网络.txt')
New-Item -Path $multiFile1 -ItemType File | Out-Null
New-Item -Path $multiFile2 -ItemType File | Out-Null
New-Item -Path $multiFile3 -ItemType File | Out-Null

$process = Start-Process -FilePath $tool -ArgumentList @('--to-traditional', '--quiet', ('"' + $multiFile1 + '"'), ('"' + $multiFile2 + '"'), ('"' + $multiFile3 + '"')) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Multi-file conversion failed: $($process.ExitCode)" }
if (-not (Test-Path -LiteralPath (Join-Path $multiTestDir (U '軟體1.txt')))) { throw 'Multi-file 1 not converted' }
if (-not (Test-Path -LiteralPath (Join-Path $multiTestDir (U '軟體2.txt')))) { throw 'Multi-file 2 not converted' }
if (-not (Test-Path -LiteralPath (Join-Path $multiTestDir (U '網路.txt')))) { throw 'Multi-file 3 not converted' }
Remove-Item -LiteralPath $multiTestDir -Recurse -Force

# Test folder-batch mode via PowerShell script (since EXE needs interactive prompt for recursive)
# We test the PowerShell script directly with -Folder and -Quiet (non-interactive, non-recursive)
$folderTestDir = Join-Path $env:TEMP 'ChineseFilenameToolFolderTest'
if (Test-Path -LiteralPath $folderTestDir) { Remove-Item -LiteralPath $folderTestDir -Recurse -Force }
New-Item -Path $folderTestDir -ItemType Directory -Force | Out-Null
$folderFile1 = Join-Path $folderTestDir (U '软件.txt')
$folderFile2 = Join-Path $folderTestDir (U '文件.txt')
$subDir = Join-Path $folderTestDir (U '子資料夾')
New-Item -Path $folderFile1 -ItemType File | Out-Null
New-Item -Path $folderFile2 -ItemType File | Out-Null
New-Item -Path $subDir -ItemType Directory | Out-Null
$subFile = Join-Path $subDir (U '视频.txt')
New-Item -Path $subFile -ItemType File | Out-Null

$psConverter = Join-Path $PSScriptRoot 'ConvertChineseName.ps1'
$process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $psConverter, '-Direction', 'ToTraditional', '-Folder', '-Quiet', $folderTestDir) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Folder-batch conversion (non-recursive) failed: $($process.ExitCode)" }
if (-not (Test-Path -LiteralPath (Join-Path $folderTestDir (U '軟體.txt')))) { throw 'Folder file 1 not converted' }
if (-not (Test-Path -LiteralPath (Join-Path $folderTestDir (U '檔案.txt')))) { throw 'Folder file 2 not converted' }
if (Test-Path -LiteralPath $subDir) { throw 'Subdirectory should not be renamed in non-recursive mode' }
if (Test-Path -LiteralPath $subFile) { throw 'Subdirectory file should not be processed in non-recursive mode' }

Remove-Item -LiteralPath $folderTestDir -Recurse -Force

Remove-Item -LiteralPath $testDirectory -Recurse -Force
Write-Host 'All EXE and PowerShell conversion tests passed.'