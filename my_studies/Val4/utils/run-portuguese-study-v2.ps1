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
#              affectgrid-portuguese-A
#              the 4 tests below in the participant's order, with the EMA survey after the 2nd:
#                vsearch-customize-portuguese         searchsizes 40,50,60 (rest default)
#                TNT-custom-stimulus-time-portuguese  StimulusDuration 4000 ms
#                maze-increasing-difficulty-v1-portuguese
#                stroop-pt                            version A, fixationTime 0 ms, isi 0 ms, blockTimeLimit 120000 ms (no per-trial limit); key-color mapping from counterbalance/stroop-pt-keys.csv
#              affectgrid-portuguese-A
#   Session B  affectgrid-portuguese-B
#              the 4 tests below in the participant's order, with the EMA survey after the 2nd:
#                ptrails-pt-portuguese
#                raven matrices (external, not PEBL)
#                tol-portuguese/TOL-portuguese
#                auditory go/no-go (external, not PEBL)
#              affectgrid-portuguese-B
#   EMA survey = Survey Ecological Momentary Assessment (external, not PEBL):
#   test 1, test 2, EMA survey, test 3, test 4.
# For an external test the script only says what to do and waits for Enter.
# PEBL tests (stroop-pt included) beep at their start and end (beeps.pbl).
# Raven matrices beeps like the PEBL tests (1000 Hz, 50 ms) when it starts (Enter = run it)
# and when Enter is pressed at its end; beeps are logged to
# counterbalance\portuguese-study-v2-external-beeps.csv.
#
# affectgrid-portuguese-A and -B are copies of affectgrid-portuguese, one per
# session, so their data are kept in separate folders. Each runs twice per
# session under the same ID. It gets addsession = 1 (params/portuguese-study.par.json),
# so from its 2nd run on it adds the ratings to the same file without asking
# "Choose new code / Add Session". Run on its own, it still asks.
#
# Counterbalancing: each participant's fixed order is read from
# counterbalance/portuguese-study-v2-orders.csv (one row per ID 1-300, columns
# participant, session_A_order, session_B_order; keys separated by spaces:
#   A: vsearch, tnt, maze, stroop (= stroop-pt)     B: ptrails, raven, tol, gonogo).
# The file is defined beforehand and only read here (the script stops if it is
# missing, if the ID has no row, or if a row does not list the session's 4 tests
# once each). Edit that file to change an order. As provided, each session
# cycles through its 4! = 24 possible orders (ID 1 = order 1, ID 25 = order 1
# again, ...), so every test is in every position equally often within each
# block of 24 IDs. Every session started is added to
# counterbalance/portuguese-study-v2-sessions.csv (time, ID, session, order).
#
# Before each test: Enter = run it, s = skip it, q = quit,
#   b = go back to the previous test (type b again to go further back), e.g. to
#   run again a test whose window was closed by accident. After the last test it
#   waits once more (Enter = finish, b = back). A PEBL test run again under the
#   same ID (other than affectgrid) asks "Choose new code / Add Session": click
#   "Add Session".
# A row per PEBL test run is added to logs/launcher-log.csv of the PEBL workspace, if there is one.
# At launch the Windows volume (default playback device) is set to 100% and unmuted.
# At the end (also after q = quit) it asks whether to save the results; y runs
# save-portuguese-study-v2-results.bat with this ID and session (it then asks
# only where to save).

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

# Windows volume of the default playback device to 100% and unmuted (see set-volume-max.ps1);
# if that fails the study still runs, with a warning to set the volume by hand
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

# Start/end beep for external tests: the same tone as the PEBL tests' BeepsStart()/BeepsEnd()
# (utils/beeps.pbl: 1000 Hz, 50 ms, amplitude 0.8, 44.1 kHz 16-bit mono), built in memory.
# Each beep is logged to counterbalance\portuguese-study-v2-external-beeps.csv
$beepsLog = Join-Path $studyDir 'counterbalance\portuguese-study-v2-external-beeps.csv'
$beepPlayer = $null
function Get-BeepPlayer {
  if ($script:beepPlayer) { return $script:beepPlayer }
  $sr = 44100; $f = 1000; $d = 50; $a = 0.8
  $n = [int]($sr * $d / 1000)
  $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter($ms)
  $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n * 2)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
  $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$sr); $w.Write([int]($sr * 2)); $w.Write([int16]2); $w.Write([int16]16)
  $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]($n * 2))
  for ($i = 0; $i -lt $n; $i++) { $w.Write([int16][Math]::Round(32767 * $a * [Math]::Sin(2 * [Math]::PI * $f * $i / $sr))) }
  $w.Flush(); $ms.Position = 0
  $p = New-Object System.Media.SoundPlayer($ms)
  $p.Load()
  $script:beepPlayer = $p
  return $p
}
function Play-Beep([string]$test, [string]$event) {
  try {
    $p = Get-BeepPlayer
    $now = Get-Date
    $p.PlaySync()
    if (-not (Test-Path $beepsLog)) {
      [IO.File]::WriteAllText($beepsLog, "participant,session,test,event,freq,durationms,amplitude,clocktime`r`n", $utf8NoBom)
    }
    $row = '{0},{1},{2},{3},1000,50,0.8,{4}' -f $id, $Session, $test, $event, $now.ToString('yyyy-MM-dd HH:mm:ss.fff')
    [IO.File]::AppendAllText($beepsLog, "$row`r`n", $utf8NoBom)
  } catch {
    Write-Host "  Could not play the $event beep ($($_.Exception.Message))." -ForegroundColor Yellow
  }
}

# A test done outside PEBL: say what to do and wait until it is finished.
# With a beepTest name (Raven), a beep plays when it starts and again when Enter is pressed at the end.
function Run-External([string]$what, [string]$beepTest = $null) {
  if ($beepTest) { Play-Beep $beepTest 'beep_start' }
  Write-Host "  Do the $what now, outside PEBL." -ForegroundColor Magenta
  $null = Read-Host '  Press Enter when it is finished'
  if ($beepTest) { Play-Beep $beepTest 'beep_end' }
}

# One step of the session: a PEBL test (Folder, Pbl, optional Params json) or an
# external test (External = what to tell the experimenter; BeepTest = name to log
# start/end beeps under, or $null for no beeps)
function Step([string]$name, [string]$folder, [string]$pblName, [string]$params = $null, [string]$external = $null, [string]$beepTest = $null) {
  [pscustomobject]@{ Name = $name; Folder = $folder; Pbl = $pblName; Params = $params; External = $external; BeepTest = $beepTest }
}
function Run-Step($t) {
  if ($t.External) { Run-External $t.External $t.BeepTest; return }
  if ($t.Params) {
    Write-Params $t.Folder $t.Params
    Run-Test $t.Folder $t.Pbl 'portuguese-study.par.json'
  } else {
    Run-Test $t.Folder $t.Pbl $null
  }
}

$affectName = "affectgrid-portuguese-$Session"
$affect  = Step $affectName $affectName $affectName "{`r`n  `"addsession`": 1`r`n}`r`n"
$bigfive = Step 'bigfive-portuguese' 'bigfive-portuguese' 'bigfive-portuguese'

# Counterbalanced tests (one step each)
$tests = @{
  vsearch = Step 'vsearch-customize-portuguese (search sizes 40,50,60)' 'vsearch-customize-portuguese' 'vsearch-customize-portuguese' "{`r`n  `"searchsizes`": [40,50,60]`r`n}`r`n"
  tnt     = Step 'TNT-custom-stimulus-time-portuguese (stimulus 4000 ms)' 'TNT-custom-stimulus-time-portuguese' 'TNT-custom-stimulus-time-portuguese' "{`r`n  `"StimulusDuration`": 4000`r`n}`r`n"
  maze    = Step 'maze-increasing-difficulty-v1-portuguese' 'maze-increasing-difficulty-v1-portuguese' 'maze-increasing-difficulty-v1-portuguese'
  stroop  = Step 'stroop-pt (version A, fixation 0 ms, ISI 0 ms, 120 s per block)' 'stroop-pt' 'stroop-pt' "{`r`n  `"version`": `"A`",`r`n  `"fixationTime`": 0,`r`n  `"isi`": 0,`r`n  `"blockTimeLimit`": 120000`r`n}`r`n"
  ptrails = Step 'ptrails-pt-portuguese' 'ptrails-pt-portuguese' 'ptrails-pt-portuguese'
  raven   = Step 'raven matrices (EXTERNAL - not PEBL)' '' '' $null 'Raven matrices' 'raven'
  tol     = Step 'tol-portuguese/TOL-portuguese' 'tol-portuguese' 'TOL-portuguese'
  gonogo  = Step 'auditory go/no-go (EXTERNAL - not PEBL)' '' '' $null 'auditory go/no-go test'
}
# Between the 2nd and 3rd counterbalanced test
$ema = Step 'Survey Ecological Momentary Assessment (EXTERNAL - not PEBL)' '' '' $null 'Survey Ecological Momentary Assessment'

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
$steps += $tests[$keys[0]], $tests[$keys[1]]
$steps += $ema
$steps += $tests[$keys[2]], $tests[$keys[3]]
$steps += $affect

if (-not (Test-Path $sessionsLog)) {
  [IO.File]::WriteAllText($sessionsLog, "time,participant,session,order_number,order`r`n", $utf8NoBom)
}
$row = '{0},{1},{2},{3},{4}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $id, $Session, $orderNo, ($keys -join ' > ')
[IO.File]::AppendAllText($sessionsLog, "$row`r`n", $utf8NoBom)

Write-Host ""
Write-Host "Portuguese study v2 - participant $id, session $Session (order $orderNo of $($orders.Count), from portuguese-study-v2-orders.csv)" -ForegroundColor Cyan
for ($i = 0; $i -lt $steps.Count; $i++) { Write-Host "  $($i + 1). $($steps[$i].Name)" }

## Step $i is next; b moves back one step (type b again to go further back),
## e.g. to run a test again whose window was closed by accident. After the last
## step it waits once more, so the last test can be gone back to as well.
$quit = $false
$i = 0
while ($i -le $steps.Count) {
  Write-Host ""
  if ($i -eq $steps.Count) {
    Write-Host "All $($steps.Count) steps done." -ForegroundColor Cyan
    $answer = $null
    while ($answer -ne '' -and $answer -ne 'b') {
      $answer = "$(Read-Host '  Enter = finish, b = back to the previous test')".Trim().ToLower()
    }
    if ($answer -eq 'b') { $i--; continue }
    break
  }
  $t = $steps[$i]
  Write-Host "Next ($($i + 1)/$($steps.Count)): $($t.Name)" -ForegroundColor Cyan
  $answer = $null
  while ($answer -ne '' -and $answer -ne 's' -and $answer -ne 'b' -and $answer -ne 'q') {
    $answer = "$(Read-Host '  Enter = run it, s = skip, b = back to the previous test, q = quit')".Trim().ToLower()
  }
  if ($answer -eq 'q') { $quit = $true; break }
  if ($answer -eq 'b') {
    if ($i -eq 0) { Write-Host '  This is the first test.' -ForegroundColor Yellow } else { $i-- }
    continue
  }
  if ($answer -eq 's') { Write-Host '  skipped' }
  else {
    try { Run-Step $t }
    catch { Write-Host "  $($t.Name) failed: $($_.Exception.Message)" -ForegroundColor Red }
  }
  $i++
}

Write-Host ""
if ($quit) { Write-Host "Stopped before: $($steps[$i].Name)" -ForegroundColor Yellow } else { Write-Host "Session $Session done." -ForegroundColor Green }

# Save the results of this session now?
$answer = $null
while ($answer -ne 'y' -and $answer -ne 'n') {
  $answer = "$(Read-Host "Save the results of participant $id, session $Session now? (y/n)")".Trim().ToLower()
}
if ($answer -eq 'y') {
  $saveBat = Join-Path $studyDir 'save-portuguese-study-v2-results.bat'
  if (Test-Path $saveBat) { & $saveBat $id $Session }
  else { Write-Host "Not found: $saveBat - run it by hand." -ForegroundColor Red }
}
