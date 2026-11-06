# Runs the maze-increasing-difficulty-v1 test for one participant: the practice
# maze, then 8 stored mazes from the shortest "shortest path" to the longest.
#
# Usage: double-click run-maze-increasing-difficulty-v1.bat in the study folder, or
#   run-maze-increasing-difficulty-v1.bat -Participant PART_0042 -Fullscreen
#   run-maze-increasing-difficulty-v1.bat -Participant PART_0042 -Language pt
#
# It asks for the participant code, prints the 8 mazes in the order they are
# presented with each maze's shortest path (number of cells from start to end,
# both included), then waits for Enter. The mazes and their order are fixed (the
# default "mazes" parameter of the test, the same list as $mazes below):
#   1-5  stored 15x15 mazes 4, 2, 16, 21, 9 (standard25)     29, 35, 43, 51, 57
#   6-8  20x20 mazes, maze-custom-dimension seeds 83, 117, 165  65, 73, 81
# The test runs like
#   pebl2.exe tests/maze-increasing-difficulty-v1/maze-increasing-difficulty-v1.pbl -s <code> --language <lang> [--fullscreen]
# from the test's folder, so data goes to tests/maze-increasing-difficulty-v1/data/<code>/:
# one csv for all the mazes, plus ONE JSON file with all the mazes presented
# (maze-increasing-difficulty-v1-<code>-<YYYYMMDD-HHMMSS of the run>-mazes.json).
# A row is added to logs/launcher-log.csv of the PEBL workspace, if there is one.

param(
  [string]$Participant,
  [string]$Language = 'en',
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$testName   = 'maze-increasing-difficulty-v1'
$studyDir   = Split-Path $PSScriptRoot -Parent
$testDir    = Join-Path $studyDir "tests\$testName"
$testFile   = Join-Path $testDir "$testName.pbl"
$mazesDir   = Join-Path $testDir 'mazes'
$ordersFile = Join-Path $studyDir 'counterbalance\task-orders.csv'
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
if (-not (Test-Path $testFile)) { throw "Test not found: $testFile" }

# The mazes, in the order presented (same list as the test's "mazes" parameter)
$mazes = @('1-maze15x15-id4.json', '2-maze15x15-id2.json', '3-maze15x15-id16.json',
           '4-maze15x15-id21.json', '5-maze15x15-id9.json', '6-maze20x20-seed83.json',
           '7-maze20x20-seed117.json', '8-maze20x20-seed165.json')

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

# Size and shortest path of a stored maze: breadth-first search from the start cell
# to the end cell through open walls (0 = no wall). Counts cells, start and end included.
function Get-MazeInfo([string]$file) {
  $m = [IO.File]::ReadAllText((Join-Path $mazesDir $file)) | ConvertFrom-Json
  $w = [int]$m.WIDTH
  $walls = @($m.NORTH, $m.SOUTH, $m.EAST, $m.WEST)
  $steps = @(-$w, $w, 1, -1)
  $start = $w * ([int]$m.START[0] - 1) + [int]$m.START[1]
  $end   = $w * ([int]$m.END[0] - 1) + [int]$m.END[1]
  $dist = @{ $start = 1 }
  $queue = New-Object System.Collections.Generic.Queue[int]
  $queue.Enqueue($start)
  while ($queue.Count -gt 0) {
    $cell = $queue.Dequeue()
    if ($cell -eq $end) { return [pscustomobject]@{ Size = "$($m.WIDTH)x$($m.HEIGHT)"; Shortest = $dist[$cell] } }
    for ($k = 0; $k -lt 4; $k++) {
      $next = $cell + $steps[$k]
      if ($walls[$k][$cell - 1] -eq 0 -and $next -ge 1 -and $next -le [int]$m.SIZE -and -not $dist.ContainsKey($next)) {
        $dist[$next] = $dist[$cell] + 1
        $queue.Enqueue($next)
      }
    }
  }
  throw "Maze $file has no path from start to end."
}

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

Write-Host ""
Write-Host "Practice maze (5x5), then:"
Write-Host "Order  Maze                      Size   Shortest path"
for ($i = 0; $i -lt $mazes.Count; $i++) {
  $info = Get-MazeInfo $mazes[$i]
  Write-Host ('{0,5}  {1,-24}  {2,-5}  {3,13}' -f ($i + 1), $mazes[$i].Replace('.json', ''), $info.Size, $info.Shortest)
}
Write-Host ""
$answer = $null
while ($answer -ne '') {
  $answer = "$(Read-Host 'Press Enter to start the test')".Trim()
}

$peblArgs = @("`"$testFile`"", '-s', $Participant, '--language', $Language)
if ($Fullscreen) { $peblArgs += '--fullscreen' }
Write-Host ""
Write-Host "Running $testName..."
$start = Get-Date
$p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory $testDir -Wait -PassThru
$secs = [int]((Get-Date) - $start).TotalSeconds
Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

if ($log) {
  $fs = if ($Fullscreen) { 'true' } else { 'false' }
  $row = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $testFile, $Participant, $Language, $fs, $p.ExitCode, $secs
  [IO.File]::AppendAllText($log, "$row`r`n", $utf8NoBom)
}
