# Portuguese study v2: runs the European Portuguese versions of the tests for
# one participant and one session, with a counterbalanced middle part.
#
# Usage: double-click run-portuguese-study-v2.bat in the study folder, or
#   run-portuguese-study-v2.bat -Participant 42 -Session A
#   run-portuguese-study-v2.bat -Participant 42 -Session B -Fullscreen
#
# It asks for
#   participant ID  a whole number from 1 to 300; the data of every test go to
#                   tests/<test>/data/<ID>/. If any test already has data for
#                   that ID (or the ID is in the sessions log), it says so and
#                   asks whether to go on with that ID or type another one.
#   session         A or B
# and runs
#   Session A  bigfive-portuguese
#              affectgrid-portuguese
#              the 4 tests below in the participant's order, each followed by its survey:
#                vsearch-customize-portuguese         searchsizes 40,50,60 (rest default)  + survey-vsearch
#                TNT-custom-stimulus-time-portuguese  StimulusDuration 4000 ms             + survey-TNT
#                maze-increasing-difficulty-v1-portuguese                                  + survey-maze
#                stroop (external, not PEBL)                                               + survey-stroop
#              affectgrid-portuguese
#   Session B  affectgrid-portuguese
#              the 4 tests below in the participant's order, each followed by its survey:
#                ptrails-pt-portuguese                                                     + survey-ptrails
#                raven matrices (external, not PEBL)                                       + survey-raven
#                tol-portuguese/TOL-portuguese                                             + survey-tol
#                auditory go/no-go (external, not PEBL)                                    + survey-gonogo (run only if that test exists)
#              affectgrid-portuguese
# For an external test the script only says what to do and waits for Enter.
#
# affectgrid-portuguese runs twice per session under the same ID (and again in
# the other session): from its 2nd run on PEBL asks "Choose new code / Add
# Session"; click "Add Session" so the ratings are added to the same file.
#
# Counterbalancing: each participant's fixed order is read from
# counterbalance/portuguese-study-v2-orders.csv (one row per ID 1-300, columns
# participant, session_A_order, session_B_order; keys separated by spaces:
#   A: vsearch, tnt, maze, stroop     B: ptrails, raven, tol, gonogo).
# The file is defined beforehand and only read here (the script stops if it is
# missing, if the ID has no row, or if a row does not list the session's 4 tests
# once each). Edit that file to change an order. As provided, each session
# cycles through its 4! = 24 possible orders (ID 1 = order 1, ID 25 = order 1
# again, ...), so every test is in every position equally often within each
# block of 24 IDs. Every session started is added to
# counterbalance/portuguese-study-v2-sessions.csv (time, ID, session, order).
#
# Before each test: Enter = run it, s = skip it, q = quit.
# A row per PEBL test run is added to logs/launcher-log.csv of the PEBL workspace, if there is one.

param(
  [string]$Participant,
  [string]$Session,
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$language    = 'pt'
$utilsDir    = $PSScriptRoot
$studyDir    = Split-Path $utilsDir -Parent
$utf8NoBom   = New-Object System.Text.UTF8Encoding($false)
$ordersFile  = Join-Path $studyDir 'counterbalance\portuguese-study-v2-orders.csv'
$sessionsLog = Join-Path $studyDir 'counterbalance\portuguese-study-v2-sessions.csv'

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

# Counterbalanced tests of each session (keys used in the orders file)
$poolA = @('vsearch', 'tnt', 'maze', 'stroop')
$poolB = @('ptrails', 'raven', 'tol', 'gonogo')

# Every order of 4 tests (4! = 24), in lexicographic order of the pool
# (only used to number the order in the sessions log; the order itself comes
# from portuguese-study-v2-orders.csv)
function Get-Orders([string[]]$pool) {
  $list = New-Object System.Collections.ArrayList
  foreach ($a in 0..3) { foreach ($b in 0..3) { foreach ($c in 0..3) { foreach ($d in 0..3) {
    if (@($a, $b, $c, $d | Select-Object -Unique).Count -eq 4) {
      [void]$list.Add(@($pool[$a], $pool[$b], $pool[$c], $pool[$d]))
    }
  } } } }
  return ,$list
}
$ordersA = Get-Orders $poolA
$ordersB = Get-Orders $poolB

# Orders file: defined beforehand, the script only reads it
if (-not (Test-Path $ordersFile)) { throw "Orders file not found: $ordersFile" }

# Data already saved for an ID: test folders with a data/<ID>/ folder that has files,
# and the sessions already started in the sessions log
function Get-ExistingData([int]$n) {
  $found = @()
  foreach ($dir in (Get-ChildItem -Path (Join-Path $studyDir 'tests') -Directory)) {
    $d = Join-Path $dir.FullName "data\$n"
    if (Test-Path $d) {
      $files = @(Get-ChildItem -Path $d -File -Recurse)
      if ($files.Count -gt 0) { $found += "  tests\$($dir.Name)\data\$n ($($files.Count) file(s), last $(($files | Sort-Object LastWriteTime | Select-Object -Last 1).LastWriteTime.ToString('yyyy-MM-dd HH:mm')))" }
    }
  }
  if (Test-Path $sessionsLog) {
    foreach ($r in (Import-Csv $sessionsLog | Where-Object { "$($_.participant)".Trim() -eq "$n" })) {
      $found += "  sessions log: session $($r.session) started $($r.time)"
    }
  }
  return ,$found
}

# Participant ID: whole number from 1 to 300; warn if data for it already exist
$id = 0
while ($true) {
  if (-not $Participant) { $Participant = Read-Host 'Participant ID (1-300)' }
  $n = 0
  if (-not ([int]::TryParse($Participant.Trim(), [ref]$n) -and $n -ge 1 -and $n -le 300)) {
    Write-Host "  Type a whole number from 1 to 300." -ForegroundColor Yellow
    $Participant = $null
    continue
  }
  $existing = Get-ExistingData $n
  if ($existing.Count -eq 0) { $id = $n; break }
  Write-Host "  Data for participant $n already exist:" -ForegroundColor Yellow
  $existing | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
  $answer = "$(Read-Host '  Enter = go on with this ID, n = type another ID')".Trim().ToLower()
  if ($answer -eq '') { $id = $n; break }
  $Participant = $null
}
$Participant = "$id"

# Session: A or B
while ($true) {
  if (-not $Session) { $Session = Read-Host 'Session (A or B)' }
  $Session = $Session.Trim().ToUpper()
  if ($Session -eq 'A' -or $Session -eq 'B') { break }
  Write-Host "  Type A or B." -ForegroundColor Yellow
  $Session = $null
}

# Runs one test with pebl2 from its own folder (data go to tests/<folder>/data/<ID>/)
function Run-Test([string]$folder, [string]$pblName, [string]$parFile) {
  $testDir  = Join-Path $studyDir "tests\$folder"
  $testFile = Join-Path $testDir "$pblName.pbl"
  if (-not (Test-Path $testFile)) { throw "Test not found: $testFile" }
  $peblArgs = @("`"$testFile`"", '-s', $Participant, '--language', $language)
  if ($parFile) { $peblArgs += @('--pfile', $parFile) }   # pebl2 looks for it in the test's params/ folder
  if ($Fullscreen) { $peblArgs += '--fullscreen' }
  Write-Host "Running $folder..."
  $start = Get-Date
  $p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory $testDir -Wait -PassThru
  $secs = [int]((Get-Date) - $start).TotalSeconds
  Write-Host "  finished (exit code $($p.ExitCode), $secs s)"
  if ($log) {
    $fs = if ($Fullscreen) { 'true' } else { 'false' }
    $row = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $testFile, $Participant, $language, $fs, $p.ExitCode, $secs
    [IO.File]::AppendAllText($log, "$row`r`n", $utf8NoBom)
  }
}

# Writes a parameter file into a test's params/ folder (values not in it keep the test's defaults)
function Write-Params([string]$folder, [string]$json) {
  $dir = Join-Path $studyDir "tests\$folder\params"
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  [IO.File]::WriteAllText((Join-Path $dir 'portuguese-study.par.json'), $json, $utf8NoBom)
}

# A test done outside PEBL: say what to do and wait until it is finished
function Run-External([string]$what) {
  Write-Host "  Do the $what now, outside PEBL." -ForegroundColor Magenta
  $null = Read-Host '  Press Enter when it is finished'
}

# One step of the session: a PEBL test (Folder, Pbl, optional Params json) or an
# external test (External = what to tell the experimenter)
function Step([string]$name, [string]$folder, [string]$pblName, [string]$params = $null, [string]$external = $null) {
  [pscustomobject]@{ Name = $name; Folder = $folder; Pbl = $pblName; Params = $params; External = $external }
}
function Run-Step($t) {
  if ($t.External) { Run-External $t.External; return }
  if ($t.Params) {
    Write-Params $t.Folder $t.Params
    Run-Test $t.Folder $t.Pbl 'portuguese-study.par.json'
  } else {
    Run-Test $t.Folder $t.Pbl $null
  }
}

$affect  = Step 'affectgrid-portuguese' 'affectgrid-portuguese' 'affectgrid-portuguese'
$bigfive = Step 'bigfive-portuguese' 'bigfive-portuguese' 'bigfive-portuguese'

# Counterbalanced tests: the test, then its survey
$tests = @{
  vsearch = @(
    (Step 'vsearch-customize-portuguese (search sizes 40,50,60)' 'vsearch-customize-portuguese' 'vsearch-customize-portuguese' "{`r`n  `"searchsizes`": [40,50,60]`r`n}`r`n"),
    (Step 'survey-vsearch' 'survey-vsearch' 'survey-vsearch'))
  tnt = @(
    (Step 'TNT-custom-stimulus-time-portuguese (stimulus 4000 ms)' 'TNT-custom-stimulus-time-portuguese' 'TNT-custom-stimulus-time-portuguese' "{`r`n  `"StimulusDuration`": 4000`r`n}`r`n"),
    (Step 'survey-TNT' 'survey-TNT' 'survey-TNT'))
  maze = @(
    (Step 'maze-increasing-difficulty-v1-portuguese' 'maze-increasing-difficulty-v1-portuguese' 'maze-increasing-difficulty-v1-portuguese'),
    (Step 'survey-maze' 'survey-maze' 'survey-maze'))
  stroop = @(
    (Step 'stroop (EXTERNAL - not PEBL)' '' '' $null 'Stroop test'),
    (Step 'survey-stroop' 'survey-stroop' 'survey-stroop'))
  ptrails = @(
    (Step 'ptrails-pt-portuguese' 'ptrails-pt-portuguese' 'ptrails-pt-portuguese'),
    (Step 'survey-ptrails' 'survey-ptrails' 'survey-ptrails'))
  raven = @(
    (Step 'raven matrices (EXTERNAL - not PEBL)' '' '' $null 'Raven matrices'),
    (Step 'survey-raven' 'survey-raven' 'survey-raven'))
  tol = @(
    (Step 'tol-portuguese/TOL-portuguese' 'tol-portuguese' 'TOL-portuguese'),
    (Step 'survey-tol' 'survey-tol' 'survey-tol'))
  gonogo = @(
    (Step 'auditory go/no-go (EXTERNAL - not PEBL)' '' '' $null 'auditory go/no-go test'))
}
# There is no survey-gonogo test yet: it is added after go/no-go only if its folder exists
if (Test-Path (Join-Path $studyDir 'tests\survey-gonogo\survey-gonogo.pbl')) {
  $tests.gonogo += (Step 'survey-gonogo' 'survey-gonogo' 'survey-gonogo')
}

$orders = if ($Session -eq 'A') { $ordersA } else { $ordersB }
$pool   = if ($Session -eq 'A') { $poolA } else { $poolB }

# This participant's fixed order for this session, from the orders file
$entry = Import-Csv $ordersFile | Where-Object { "$($_.participant)".Trim() -eq "$id" } | Select-Object -First 1
if (-not $entry) { throw "Participant $id is not in $ordersFile." }
$column = "session_$($Session)_order"
$keys   = @("$($entry.$column)".Trim().ToLower() -split '\s+' | Where-Object { $_ })
if ($keys.Count -ne $pool.Count -or @(Compare-Object ($keys | Sort-Object) ($pool | Sort-Object)).Count -gt 0) {
  throw "Order '$($entry.$column)' for participant $id in $ordersFile must list $($pool -join ', ') once each (any order)."
}
$orderNo = 0
for ($k = 0; $k -lt $orders.Count; $k++) { if (($orders[$k] -join ' ') -eq ($keys -join ' ')) { $orderNo = $k + 1 } }

# The whole session
$steps = @()
if ($Session -eq 'A') { $steps += $bigfive }
$steps += $affect
foreach ($key in $keys) { $steps += $tests[$key] }
$steps += $affect

if (-not (Test-Path $sessionsLog)) {
  [IO.File]::WriteAllText($sessionsLog, "time,participant,session,order_number,order`r`n", $utf8NoBom)
}
$row = '{0},{1},{2},{3},{4}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $id, $Session, $orderNo, ($keys -join ' > ')
[IO.File]::AppendAllText($sessionsLog, "$row`r`n", $utf8NoBom)

Write-Host ""
Write-Host "Portuguese study v2 - participant $id, session $Session (order $orderNo of $($orders.Count), from portuguese-study-v2-orders.csv)" -ForegroundColor Cyan
for ($i = 0; $i -lt $steps.Count; $i++) { Write-Host "  $($i + 1). $($steps[$i].Name)" }
Write-Host "affectgrid-portuguese: if PEBL asks 'Choose new code / Add Session', click 'Add Session'." -ForegroundColor DarkGray

$quit = $false
for ($i = 0; $i -lt $steps.Count; $i++) {
  $t = $steps[$i]
  Write-Host ""
  Write-Host "Next ($($i + 1)/$($steps.Count)): $($t.Name)" -ForegroundColor Cyan
  $answer = $null
  while ($answer -ne '' -and $answer -ne 's' -and $answer -ne 'q') {
    $answer = "$(Read-Host '  Enter = run it, s = skip, q = quit')".Trim().ToLower()
  }
  if ($answer -eq 'q') { $quit = $true; break }
  if ($answer -eq 's') { Write-Host '  skipped'; continue }
  try { Run-Step $t }
  catch { Write-Host "  $($t.Name) failed: $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Host ""
if ($quit) { Write-Host "Stopped before: $($steps[$i].Name)" -ForegroundColor Yellow } else { Write-Host "Session $Session done." -ForegroundColor Green }
