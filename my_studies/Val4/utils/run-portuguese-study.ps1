# Portuguese study: runs the European Portuguese versions of the tests for one
# participant and one session, in a counterbalanced order.
#
# Usage: double-click run-portuguese-study.bat in the study folder, or
#   run-portuguese-study.bat -Participant 42 -Session A
#   run-portuguese-study.bat -Participant 42 -Session B -Fullscreen
#
# It asks for
#   participant ID  a whole number from 1 to 300; the data of every test go to
#                   tests/<test>/data/<ID>/
#   session         A or B
# and runs
#   Session A  vsearch-customize-portuguese        searchsizes 40,50,60 (rest default)
#              TNT-custom-stimulus-time-portuguese StimulusDuration 4000 ms
#              maze-increasing-difficulty-v1-portuguese
#   Session B  ptrails-pt-portuguese
#              tol-portuguese/TOL-portuguese
#
# Counterbalancing: each participant's fixed test order is read from
# counterbalance/portuguese-study-orders.csv (one row per ID 1-300, columns
# participant, session_A_order, session_B_order; test names separated by spaces:
# vsearch, tnt, maze, ptrails, tol). Edit that file to change an order.
# As generated, session A cycles through the 6 possible orders (ID 1 = order 1,
# ID 7 = order 1 again, ...) and session B through the 2, so every order is used
# about equally. Every session started is added to
# counterbalance/portuguese-study-sessions.csv (time, ID, session, order).
#
# Before each test: Enter = run it, s = skip it, q = quit.
# A row per test run is added to logs/launcher-log.csv of the PEBL workspace, if there is one.

param(
  [string]$Participant,
  [string]$Session,
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$language   = 'pt'
$utilsDir   = $PSScriptRoot
$studyDir   = Split-Path $utilsDir -Parent
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
$sessionsLog = Join-Path $studyDir 'counterbalance\portuguese-study-sessions.csv'

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

# Participant ID: whole number from 1 to 300
$id = 0
while ($true) {
  if (-not $Participant) { $Participant = Read-Host 'Participant ID (1-300)' }
  $n = 0
  if ([int]::TryParse($Participant.Trim(), [ref]$n) -and $n -ge 1 -and $n -le 300) { $id = $n; break }
  Write-Host "  Type a whole number from 1 to 300." -ForegroundColor Yellow
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

# Runs one Portuguese test with pebl2 from its own folder (data go to tests/<folder>/data/<ID>/)
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
  $file = Join-Path $studyDir "tests\$folder\params\portuguese-study.par.json"
  [IO.File]::WriteAllText($file, $json, $utf8NoBom)
}

$tests = @{
  vsearch = [pscustomobject]@{ Name = 'vsearch-customize-portuguese (search sizes 40,50,60)'
    Run = {
      Write-Params 'vsearch-customize-portuguese' "{`r`n  `"searchsizes`": [40,50,60]`r`n}`r`n"
      Run-Test 'vsearch-customize-portuguese' 'vsearch-customize-portuguese' 'portuguese-study.par.json'
    } }
  tnt = [pscustomobject]@{ Name = 'TNT-custom-stimulus-time-portuguese (stimulus 4000 ms)'
    Run = {
      Write-Params 'TNT-custom-stimulus-time-portuguese' "{`r`n  `"StimulusDuration`": 4000`r`n}`r`n"
      Run-Test 'TNT-custom-stimulus-time-portuguese' 'TNT-custom-stimulus-time-portuguese' 'portuguese-study.par.json'
    } }
  maze = [pscustomobject]@{ Name = 'maze-increasing-difficulty-v1-portuguese'
    Run = { Run-Test 'maze-increasing-difficulty-v1-portuguese' 'maze-increasing-difficulty-v1-portuguese' $null } }
  ptrails = [pscustomobject]@{ Name = 'ptrails-pt-portuguese'
    Run = { Run-Test 'ptrails-pt-portuguese' 'ptrails-pt-portuguese' $null } }
  tol = [pscustomobject]@{ Name = 'tol-portuguese/TOL-portuguese'
    Run = { Run-Test 'tol-portuguese' 'TOL-portuguese' $null } }
}

# Every possible order of each session's tests (only used to number the order
# in the sessions log; the order itself comes from portuguese-study-orders.csv)
$ordersA = @(
  @('vsearch', 'tnt', 'maze'),
  @('vsearch', 'maze', 'tnt'),
  @('tnt', 'vsearch', 'maze'),
  @('tnt', 'maze', 'vsearch'),
  @('maze', 'vsearch', 'tnt'),
  @('maze', 'tnt', 'vsearch')
)
$ordersB = @(
  @('ptrails', 'tol'),
  @('tol', 'ptrails')
)
$orders  = if ($Session -eq 'A') { $ordersA } else { $ordersB }

# This participant's fixed order for this session, from portuguese-study-orders.csv
$ordersFile = Join-Path $studyDir 'counterbalance\portuguese-study-orders.csv'
if (-not (Test-Path $ordersFile)) { throw "Orders file not found: $ordersFile" }
$entry = Import-Csv $ordersFile | Where-Object { $_.participant.Trim() -eq "$id" } | Select-Object -First 1
if (-not $entry) { throw "Participant $id is not in $ordersFile." }
$column = "session_$($Session)_order"
$keys   = @("$($entry.$column)".Trim().ToLower() -split '\s+' | Where-Object { $_ })
$valid  = @($orders[0])   # the tests this session must contain, each once
if ($keys.Count -ne $valid.Count -or @(Compare-Object ($keys | Sort-Object) ($valid | Sort-Object)).Count -gt 0) {
  throw "Order '$($entry.$column)' for participant $id in $ordersFile must list $($valid -join ', ') once each (any order)."
}
$orderNo = 0
for ($k = 0; $k -lt $orders.Count; $k++) { if (($orders[$k] -join ' ') -eq ($keys -join ' ')) { $orderNo = $k + 1 } }
$steps   = @($keys | ForEach-Object { $tests[$_] })

if (-not (Test-Path $sessionsLog)) {
  [IO.File]::WriteAllText($sessionsLog, "time,participant,session,order_number,order`r`n", $utf8NoBom)
}
$row = '{0},{1},{2},{3},{4}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $id, $Session, $orderNo, ($keys -join ' > ')
[IO.File]::AppendAllText($sessionsLog, "$row`r`n", $utf8NoBom)

Write-Host ""
Write-Host "Portuguese study - participant $id, session $Session (order $orderNo of $($orders.Count), from portuguese-study-orders.csv)" -ForegroundColor Cyan
for ($i = 0; $i -lt $steps.Count; $i++) { Write-Host "  $($i + 1). $($steps[$i].Name)" }

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
  try { & $t.Run }
  catch { Write-Host "  $($t.Name) failed: $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Host ""
if ($quit) { Write-Host "Stopped before: $($steps[$i].Name)" -ForegroundColor Yellow } else { Write-Host "Session $Session done." -ForegroundColor Green }
