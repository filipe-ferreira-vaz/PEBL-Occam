# Runs the maze-custom-dimension test for one participant: one new square
# maze with the dimension typed in the terminal.
#
# Usage: double-click run-maze-custom-dimension.bat in the study folder, or
#   run-maze-custom-dimension.bat -Participant PART_0042 -Dimension 20
#   run-maze-custom-dimension.bat -Participant PART_0042 -Dimension 20 -Seed 481516 -Fullscreen
#
# It asks for
#   participant code
#   dimension  N, for an N x N maze (2-50)
#   seed       Enter = a new random seed; type a seed to present a maze again
# then prints the dimension and seed and waits for Enter (or c to choose again).
# The same dimension + seed always gives the same maze.
# They are written to tests/maze-custom-dimension/params/dimension.par.json and the test runs like
#   pebl2.exe tests/maze-custom-dimension/maze-custom-dimension.pbl -s <code> --language <lang> --pfile dimension.par.json [--fullscreen]
# (pebl2 looks for the --pfile file in the test's params/ folder)
# from the test's folder, so data goes to tests/maze-custom-dimension/data/<code>/:
# the csv (with seed, width, height) and the maze as JSON
# (maze-custom-dimension-<code>-<YYYYMMDD-HHMMSS of the run>-<N>x<N>-seed<seed>.json).
# A row with the dimension and seed is added to tests/maze-custom-dimension/data/runs.csv,
# and one to logs/launcher-log.csv of the PEBL workspace, if there is one.

param(
  [string]$Participant,
  [string]$Language = 'en',
  [int]$Dimension = 0,
  [int]$Seed = 0,
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$testName   = 'maze-custom-dimension'
$minDim     = 2
$maxDim     = 50
$studyDir   = Split-Path $PSScriptRoot -Parent
$testDir    = Join-Path $studyDir "tests\$testName"
$testFile   = Join-Path $testDir "$testName.pbl"
$parFile    = Join-Path $testDir 'params\dimension.par.json'
$runsFile   = Join-Path $testDir 'data\runs.csv'
$ordersFile = Join-Path $studyDir 'counterbalance\task-orders.csv'
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
if (-not (Test-Path $testFile)) { throw "Test not found: $testFile" }

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

# Participant code: listed in task-orders.csv if the study has one, else any CODE_1234
$known = $null
if (Test-Path $ordersFile) {
  $known = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($l in ([IO.File]::ReadAllLines($ordersFile) | Select-Object -Skip 1)) { if ($l) { [void]$known.Add($l.Split(',')[0]) } }
}
while ($true) {
  if (-not $Participant) { $Participant = Read-Host 'Participant code' }
  $Participant = $Participant.Trim().ToUpper()
  if ($Participant -match '^[A-Z0-9]+_\d+$' -and (-not $known -or $known.Contains($Participant))) { break }
  if ($known) { Write-Host "  '$Participant' is not in counterbalance\task-orders.csv." -ForegroundColor Yellow }
  else { Write-Host "  '$Participant' is not a valid code (e.g. PART_0001)." -ForegroundColor Yellow }
  $Participant = $null
}

# Asks for a whole number from $min to $max; Enter = $default (if $default is not $null)
function Read-Int([string]$prompt, $default, [int]$min, [int]$max) {
  while ($true) {
    $shown = if ($null -ne $default) { " ($default)" } else { '' }
    $answer = "$(Read-Host "$prompt$shown")".Trim()
    if (-not $answer -and $null -ne $default) { return [int]$default }
    $n = 0
    if ([int]::TryParse($answer, [ref]$n) -and $n -ge $min -and $n -le $max) { return $n }
    Write-Host "  Type a whole number from $min to $max." -ForegroundColor Yellow
  }
}

$askDimension = ($Dimension -lt $minDim -or $Dimension -gt $maxDim)
$askSeed = ($Seed -le 0)
while ($true) {
  Write-Host ""
  if ($askDimension) {
    $Dimension = Read-Int "Maze dimension N, for an N x N maze ($minDim-$maxDim)" 15 $minDim $maxDim
  }
  if ($askSeed) {
    $answer = "$(Read-Host 'Seed (Enter = new random seed; type a seed to present a maze again)')".Trim()
    $n = 0
    if ($answer -and [int]::TryParse($answer, [ref]$n) -and $n -ge 1) { $Seed = $n }
    else {
      if ($answer) { Write-Host "  '$answer' is not a whole number of 1 or more: using a new random seed." -ForegroundColor Yellow }
      $Seed = Get-Random -Minimum 26 -Maximum 1000026   # 1-25 are the stored mazes' seeds
    }
  }

  Write-Host ""
  Write-Host "Maze: $Dimension x $Dimension cells, seed $Seed"
  if ($Dimension -gt 30) { Write-Host "  (a maze this big can take a while to generate)" -ForegroundColor Yellow }
  Write-Host "To present this maze again: run-maze-custom-dimension.bat -Dimension $Dimension -Seed $Seed"
  Write-Host ""
  if (-not ($askDimension -or $askSeed)) { break }
  $answer = $null
  while ($answer -ne '' -and $answer -ne 'c') {
    $answer = "$(Read-Host 'Press Enter to start the test, or type c to choose again')".Trim().ToLower()
  }
  if ($answer -eq '') { break }
  $askDimension = $true
  $askSeed = $true
}

$json = "{`r`n  `"mazeDimension`": $Dimension,`r`n  `"seed`": $Seed,`r`n  `"savemazes`": 1`r`n}`r`n"
[IO.File]::WriteAllText($parFile, $json, $utf8NoBom)

$peblArgs = @("`"$testFile`"", '-s', $Participant, '--language', $Language, '--pfile', 'dimension.par.json')
if ($Fullscreen) { $peblArgs += '--fullscreen' }
Write-Host "Running $testName ($Dimension x $Dimension, seed $Seed)..."
$start = Get-Date
$p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory $testDir -Wait -PassThru
$secs = [int]((Get-Date) - $start).TotalSeconds
Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

# Record of every run: which maze (dimension + seed) each participant got
$dataDir = Split-Path $runsFile -Parent
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory $dataDir | Out-Null }
if (-not (Test-Path $runsFile)) { [IO.File]::WriteAllText($runsFile, "datetime,participant,dimension,seed,exitcode,seconds`r`n", $utf8NoBom) }
$row = '{0},{1},{2},{3},{4},{5}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $Participant, $Dimension, $Seed, $p.ExitCode, $secs
[IO.File]::AppendAllText($runsFile, "$row`r`n", $utf8NoBom)

if ($log) {
  $fs = if ($Fullscreen) { 'true' } else { 'false' }
  $row = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $testFile, $Participant, $Language, $fs, $p.ExitCode, $secs
  [IO.File]::AppendAllText($log, "$row`r`n", $utf8NoBom)
}
