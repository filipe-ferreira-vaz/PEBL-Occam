# Trial study (Nov 5): runs a fixed list of tests for one participant.
#
# Usage: double-click trial-study-nov-5.bat in the study folder, or
#   trial-study-nov-5.bat -Participant PART_0042 -Fullscreen
#   trial-study-nov-5.bat -Participant PART_0042 -Language pt
#
# It asks for the participant name once (any name, not checked against
# counterbalance	ask-orders.csv), then runs
#   Session A
#     1. vsearch-customize         searchsizes 40,50,60; numtargs, box size: defaults
#                                  (via run-vsearch-customize.ps1)
#     2. TNT-custom-stimulus-time  StimulusDuration 4000 ms
#                                  (via run-TNT-custom-stimulus-time.ps1)
#     3. maze-custom-dimension     5 random 15 x 15 mazes, then 3 random 20 x 20 mazes,
#                                  one run each (via run-maze-custom-dimension.ps1).
#                                  Every maze is saved as JSON in
#                                  tests/maze-custom-dimension/data/<code>/, and its
#                                  dimension + seed are added to tests/maze-custom-dimension/data/runs.csv
#   Session B
#     4. ptrails-pt
#     5. tol/TOL
# Before each test: Enter = run it, s = skip it, q = quit.
# Data of each test goes to tests/<test>/data/<code>/, and a row per run is
# added to logs/launcher-log.csv of the PEBL workspace, if there is one.

param(
  [string]$Participant,
  [string]$Language = 'en',
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$utilsDir   = $PSScriptRoot
$studyDir   = Split-Path $utilsDir -Parent
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

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

# Participant name: anything (not checked against counterbalance\task-orders.csv),
# as long as it can be a folder name: letters, digits, _ and -
while ($true) {
  if (-not $Participant) { $Participant = Read-Host 'Participant name' }
  $Participant = $Participant.Trim()
  if ($Participant -match '^[A-Za-z0-9_-]+$') { break }
  Write-Host "  Use only letters, digits, _ and - (e.g. TEST_01)." -ForegroundColor Yellow
  $Participant = $null
}

# Arguments every launcher gets (-AnyParticipant: they skip their own task-orders.csv check)
$common = @{ Participant = $Participant; Language = $Language; Fullscreen = $Fullscreen; AnyParticipant = $true }

# Runs a test with pebl2 like the PEBL launcher does (for tests without their own launcher)
function Run-Plain([string]$testFolder, [string]$pblName) {
  $testDir  = Join-Path $studyDir "tests\$testFolder"
  $testFile = Join-Path $testDir "$pblName.pbl"
  if (-not (Test-Path $testFile)) { throw "Test not found: $testFile" }
  $peblArgs = @("`"$testFile`"", '-s', $Participant, '--language', $Language)
  if ($Fullscreen) { $peblArgs += '--fullscreen' }
  Write-Host "Running $testFolder/$pblName..."
  $start = Get-Date
  $p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory $testDir -Wait -PassThru
  $secs = [int]((Get-Date) - $start).TotalSeconds
  Write-Host "  finished (exit code $($p.ExitCode), $secs s)"
  if ($log) {
    $fs = if ($Fullscreen) { 'true' } else { 'false' }
    $row = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $testFile, $Participant, $Language, $fs, $p.ExitCode, $secs
    [IO.File]::AppendAllText($log, "$row`r`n", $utf8NoBom)
  }
}

# Maze runs: 5 x 15x15, then 3 x 20x20, each with its own random seed (1-25 are the stored mazes' seeds)
$mazes = @()
$usedSeeds = @{}
foreach ($dim in @(15, 15, 15, 15, 15, 20, 20, 20)) {
  do { $seed = Get-Random -Minimum 26 -Maximum 1000026 } while ($usedSeeds.ContainsKey($seed))
  $usedSeeds[$seed] = $true
  $mazes += [pscustomobject]@{ Dimension = $dim; Seed = $seed }
}

$steps = @(
  [pscustomobject]@{ Session = 'A'; Name = 'vsearch-customize (search sizes 40,50,60)'
    Run = { & (Join-Path $utilsDir 'run-vsearch-customize.ps1') @common -SearchSizes 40,50,60 } }
  [pscustomobject]@{ Session = 'A'; Name = 'TNT-custom-stimulus-time (stimulus 4000 ms)'
    Run = { & (Join-Path $utilsDir 'run-TNT-custom-stimulus-time.ps1') @common -StimulusDuration 4000 } }
)
for ($i = 0; $i -lt $mazes.Count; $i++) {
  $m = $mazes[$i]
  $steps += [pscustomobject]@{ Session = 'A'; Name = "maze-custom-dimension, maze $($i + 1) of $($mazes.Count) ($($m.Dimension) x $($m.Dimension))"
    Run = { & (Join-Path $utilsDir 'run-maze-custom-dimension.ps1') @common -Dimension $m.Dimension -Seed $m.Seed }.GetNewClosure() }
}
$steps += [pscustomobject]@{ Session = 'B'; Name = 'ptrails-pt'; Run = { Run-Plain 'ptrails-pt' 'ptrails-pt' } }
$steps += [pscustomobject]@{ Session = 'B'; Name = 'tol/TOL';    Run = { Run-Plain 'tol' 'TOL' } }

Write-Host ""
Write-Host "Trial study Nov 5 - participant $Participant" -ForegroundColor Cyan
foreach ($s in ($steps | Group-Object Session)) {
  Write-Host "  Session $($s.Name):"
  foreach ($t in $s.Group) { Write-Host "    - $($t.Name)" }
}

$session = $null
$quit = $false
for ($i = 0; $i -lt $steps.Count -and -not $quit; $i++) {
  $t = $steps[$i]
  if ($t.Session -ne $session) {
    $session = $t.Session
    Write-Host ""
    Write-Host "===== Session $session =====" -ForegroundColor Cyan
  }
  Write-Host ""
  Write-Host "Next ($($i + 1)/$($steps.Count)): $($t.Name)" -ForegroundColor Cyan
  $answer = $null
  while ($answer -ne '' -and $answer -ne 's' -and $answer -ne 'q') {
    $answer = "$(Read-Host '  Enter = run it, s = skip, q = quit')".Trim().ToLower()
  }
  if ($answer -eq 'q') { $quit = $true; break }
  if ($answer -eq 's') { Write-Host '  skipped'; continue }
  try { & $t.Run }
  catch { Write-Host "  $($t.Name) failed: $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Host ""
if ($quit) { Write-Host "Stopped before: $($steps[$i].Name)" -ForegroundColor Yellow } else { Write-Host 'Trial study done.' -ForegroundColor Green }
