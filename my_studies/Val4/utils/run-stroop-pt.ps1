# Runs the stroop-pt test (Portuguese color Stroop) for one participant.
#
# Usage: double-click run-stroop-pt.bat in the study folder, or
#   run-stroop-pt.bat -Participant 42 -Version B -Fullscreen   (nothing asked)
#
# It asks for
#   the participant ID  whole number from 1 to 300 (the IDs in
#                       counterbalance\stroop-pt-keys.csv, which sets the
#                       color-key mapping); says if stroop-pt data for that ID
#                       already exist
#   the test version    A = paper-sheet order, reading block + naming block
#                       B = 112 mixed trials (C/I/N), naming block
# The settings are written to tests/stroop-pt/params/run-stroop-pt.par.json
# (the same as in run-portuguese-study-v2: fixation 0 ms, ISI 0 ms, 120 s per
# block) and the test runs like
#   pebl2.exe tests/stroop-pt/stroop-pt.pbl -s <ID> --language pt --pfile run-stroop-pt.par.json [--fullscreen]
# from the test's folder, so data go to tests/stroop-pt/data/<ID>/.
# The Windows volume is set to 100% and unmuted first (for the start/end beeps).
# A row is added to logs/launcher-log.csv of the PEBL workspace, if there is one.

param(
  [string]$Participant,
  [string]$Version,
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$testName  = 'stroop-pt'
$language  = 'pt'
$utilsDir  = $PSScriptRoot
$studyDir  = Split-Path $utilsDir -Parent
$testDir   = Join-Path $studyDir "tests\$testName"
$testFile  = Join-Path $testDir "$testName.pbl"
$parName   = 'run-stroop-pt.par.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if (-not (Test-Path $testFile)) { throw "Test not found: $testFile" }

# Windows volume to 100% and unmuted; if that fails the test still runs
try { . (Join-Path $utilsDir 'set-volume-max.ps1'); Set-VolumeMax }
catch { Write-Host "Could not set the Windows volume ($($_.Exception.Message)). Set it to 100% and unmute it by hand." -ForegroundColor Yellow }

# PEBL workspace: first parent of the study with settings/launcher.cfg
$workspaceDir = Split-Path $studyDir -Parent
while ($workspaceDir -and -not (Test-Path (Join-Path $workspaceDir 'settings\launcher.cfg'))) {
  $workspaceDir = Split-Path $workspaceDir -Parent
}

# pebl2.exe: from the launcher settings, else the default install folder
$pebl = 'C:\Program Files (x86)\PEBL2\bin\pebl2.exe'
if ($workspaceDir) {
  $line = Select-String -Path (Join-Path $workspaceDir 'settings\launcher.cfg') -Pattern '^pebl_executable_path=(.+)$' | Select-Object -First 1
  if ($line) { $pebl = $line.Matches[0].Groups[1].Value.Trim() }
}
if (-not (Test-Path $pebl)) { throw "pebl2.exe not found at $pebl" }
$log = if ($workspaceDir) { Join-Path $workspaceDir 'logs\launcher-log.csv' } else { $null }

# Participant ID: whole number from 1 to 300; warn if stroop-pt data for it already exist
$id = 0
while ($true) {
  if (-not $Participant) { $Participant = Read-Host 'Participant ID (1-300)' }
  $n = 0
  if (-not ([int]::TryParse($Participant.Trim(), [ref]$n) -and $n -ge 1 -and $n -le 300)) {
    Write-Host "  Type a whole number from 1 to 300." -ForegroundColor Yellow
    $Participant = $null
    continue
  }
  $d = Join-Path $testDir "data\$n"
  $files = @(if (Test-Path $d) { Get-ChildItem -Path $d -File -Recurse })
  if ($files.Count -eq 0) { $id = $n; break }
  $last = ($files | Sort-Object LastWriteTime | Select-Object -Last 1).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
  Write-Host "  stroop-pt data for participant $n already exist: tests\$testName\data\$n ($($files.Count) file(s), last $last)" -ForegroundColor Yellow
  $answer = "$(Read-Host '  Enter = go on with this ID, n = type another ID')".Trim().ToLower()
  if ($answer -eq '') { $id = $n; break }
  $Participant = $null
}
$Participant = "$id"

# Test version: A or B
while ($true) {
  if (-not $Version) {
    Write-Host ""
    Write-Host "Test version:"
    Write-Host "  A = paper-sheet order (112 incongruent words), reading block + naming block"
    Write-Host "  B = 112 mixed trials (congruent / incongruent / XXXXX), naming block"
    $Version = Read-Host 'Version (A or B)'
  }
  $Version = $Version.Trim().ToUpper()
  if ($Version -eq 'A' -or $Version -eq 'B') { break }
  Write-Host "  Type A or B." -ForegroundColor Yellow
  $Version = $null
}

$json = "{`r`n  `"version`": `"$Version`",`r`n  `"fixationTime`": 0,`r`n  `"isi`": 0,`r`n  `"blockTimeLimit`": 120000`r`n}`r`n"
$parDir = Join-Path $testDir 'params'
if (-not (Test-Path $parDir)) { New-Item -ItemType Directory -Path $parDir | Out-Null }
[IO.File]::WriteAllText((Join-Path $parDir $parName), $json, $utf8NoBom)

$peblArgs = @("`"$testFile`"", '-s', $Participant, '--language', $language, '--pfile', $parName)
if ($Fullscreen) { $peblArgs += '--fullscreen' }
Write-Host ""
Write-Host "Running $testName, version $Version, participant $Participant..."
$start = Get-Date
$p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory $testDir -Wait -PassThru
$secs = [int]((Get-Date) - $start).TotalSeconds
Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

if ($log) {
  $fs = if ($Fullscreen) { 'true' } else { 'false' }
  $row = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $testFile, $Participant, $language, $fs, $p.ExitCode, $secs
  [IO.File]::AppendAllText($log, "$row`r`n", $utf8NoBom)
}
