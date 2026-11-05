# Runs the maze-custom test for one participant with the mazes, and their
# order, typed in the terminal.
#
# Usage: double-click run-maze-custom.bat in the study folder, or
#   run-maze-custom.bat -Participant PART_0042 -Fullscreen
#   run-maze-custom.bat -Participant PART_0042 -Language pt
#
# It asks for the participant code, prints the 25 stored mazes sorted by
# shortest path, then asks for
#   mazes  IDs of the stored 15x15 mazes (1-25) to present, in order, e.g. 4,18,9
# (Enter = keep the default shown in parentheses). It prints the order of the
# mazes with each maze's shortest path (number of cells from start to end,
# both included), then waits for Enter (or c to choose the mazes again).
# The list is written to tests/maze-custom/params/custom.par.json and the test runs like
#   pebl2.exe tests/maze-custom/maze-custom.pbl -s <code> --language <lang> --pfile custom.par.json [--fullscreen]
# (pebl2 looks for the --pfile file in the test's params/ folder)
# from the test's folder, so data goes to tests/maze-custom/data/<code>/,
# including one JSON file per maze presented
# (maze-custom-<code>-<YYYYMMDD-HHMMSS of the run>-<order>-maze<id>.json).
# A row is added to logs/launcher-log.csv of the PEBL workspace, if there is one.

param(
  [string]$Participant,
  [string]$Language = 'en',
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$testName   = 'maze-custom'
$studyDir   = Split-Path $PSScriptRoot -Parent
$testDir    = Join-Path $studyDir "tests\$testName"
$testFile   = Join-Path $testDir "$testName.pbl"
$parFile    = Join-Path $testDir 'params\custom.par.json'
$mazesDir   = Join-Path $testDir 'mazes'
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

# Shortest path of a stored maze: breadth-first search from the start cell to
# the end cell through open walls (0 = no wall). Counts cells, start and end included.
function Get-ShortestPath([int]$id) {
  $m = [IO.File]::ReadAllText((Join-Path $mazesDir "maze-$id.json")) | ConvertFrom-Json
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
    if ($cell -eq $end) { return $dist[$cell] }
    for ($k = 0; $k -lt 4; $k++) {
      $next = $cell + $steps[$k]
      if ($walls[$k][$cell - 1] -eq 0 -and $next -ge 1 -and $next -le [int]$m.SIZE -and -not $dist.ContainsKey($next)) {
        $dist[$next] = $dist[$cell] + 1
        $queue.Enqueue($next)
      }
    }
  }
  throw "Maze $id has no path from start to end."
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

# Asks for a comma-separated list of whole numbers from $min to $max; Enter = $default
function Read-IntList([string]$prompt, [int[]]$default, [int]$min, [int]$max) {
  while ($true) {
    $answer = "$(Read-Host "$prompt ($($default -join ','))")".Trim()
    if (-not $answer) { return $default }
    $values = @()
    $ok = $true
    foreach ($part in $answer.Split(',')) {
      $n = 0
      if ([int]::TryParse($part.Trim(), [ref]$n) -and $n -ge $min -and $n -le $max) { $values += $n } else { $ok = $false }
    }
    if ($ok) { return $values }
    Write-Host "  Type whole numbers from $min to $max separated by commas, e.g. $($default -join ',')." -ForegroundColor Yellow
  }
}

# The 25 stored mazes sorted by shortest path (same list as tests/maze/mazes-by-shortest-path.csv);
# mazes with the same shortest path share a rank
$hard5  = @(1, 9, 10, 13, 19)
$sorted = @(1..25 | ForEach-Object { [pscustomobject]@{ Maze = $_; Shortest = (Get-ShortestPath $_) } } | Sort-Object Shortest, Maze)

while ($true) {
  Write-Host ""
  Write-Host "Stored mazes, by shortest path:"
  Write-Host "Rank  Maze  Shortest path  In hard5"
  foreach ($m in $sorted) {
    $rank = 1 + @($sorted | Where-Object { $_.Shortest -lt $m.Shortest }).Count
    $inHard5 = if ($hard5 -contains $m.Maze) { 'yes' } else { '' }
    Write-Host ('{0,4}  {1,4}  {2,13}  {3}' -f $rank, $m.Maze, $m.Shortest, $inHard5)
  }
  Write-Host ""
  $mazes = @(Read-IntList 'Mazes to present (1-25), in order, separated by commas' @(1, 9, 10, 13, 19) 1 25)

  Write-Host ""
  Write-Host "Order  Maze  Shortest path"
  for ($i = 0; $i -lt $mazes.Count; $i++) {
    Write-Host ('{0,5}  {1,4}  {2,13}' -f ($i + 1), $mazes[$i], (Get-ShortestPath $mazes[$i]))
  }
  Write-Host ""
  $answer = $null
  while ($answer -ne '' -and $answer -ne 'c') {
    $answer = "$(Read-Host 'Press Enter to start the test, or type c to choose the mazes again')".Trim().ToLower()
  }
  if ($answer -eq '') { break }
}

$json = "{`r`n  `"problemset`": `"custom`",`r`n  `"problems`": [$($mazes -join ',')],`r`n  `"numProblems`": $($mazes.Count),`r`n  `"savemazes`": 1`r`n}`r`n"
[IO.File]::WriteAllText($parFile, $json, $utf8NoBom)

$peblArgs = @("`"$testFile`"", '-s', $Participant, '--language', $Language, '--pfile', 'custom.par.json')
if ($Fullscreen) { $peblArgs += '--fullscreen' }
Write-Host ""
Write-Host "Running $testName (mazes $($mazes -join ','))..."
$start = Get-Date
$p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory $testDir -Wait -PassThru
$secs = [int]((Get-Date) - $start).TotalSeconds
Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

if ($log) {
  $fs = if ($Fullscreen) { 'true' } else { 'false' }
  $row = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $testFile, $Participant, $Language, $fs, $p.ExitCode, $secs
  [IO.File]::AppendAllText($log, "$row`r`n", $utf8NoBom)
}
