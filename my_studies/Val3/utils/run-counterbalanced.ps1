# Runs the tests of the study this utils folder is in for one participant, in
# that participant's hardcoded counterbalanced order
# (<Study>/counterbalance/task-orders.csv, made by make-counterbalance-orders.ps1).
#
# Usage (or double-click <Study>/run-participant.bat):
#   powershell -ExecutionPolicy Bypass -File my_studies/<Study>/utils/run-counterbalanced.ps1
#   powershell -ExecutionPolicy Bypass -File my_studies/<Study>/utils/run-counterbalanced.ps1 -Participant PART_0042 -Fullscreen
#   powershell -ExecutionPolicy Bypass -File my_studies/<Study>/utils/run-counterbalanced.ps1 -Participant PART_0042 -StartAt 4
#
# For the participant code (asked for if not given) it:
#   1. writes the chain <Study>/chains/<code>.json (also usable in the PEBL
#      launcher)
#   2. runs each test like the launcher does:
#        pebl2.exe tests/<test>/<test>.pbl -s <code> --language <lang> [--pfile ...] [--fullscreen]
#      from the test's folder, so data goes to tests/<test>/data/<code>/
#   3. adds a row per test to logs/launcher-log.csv of the PEBL workspace the
#      study is in (the first parent folder with settings/launcher.cfg), if any
#
# Before each test (and after the last one) it waits for a command:
#   Enter  start the next test (or finish)
#   b      go back to the previous test, e.g. if its window was closed by
#          accident (type b again to go back further)
#   q      quit (prints the -StartAt command to continue later)
#
# -StartAt N skips the first N-1 tests (to resume after a crash).
# -DryRun writes the chain and prints the commands without running anything.

param(
  [string]$Participant,
  [string]$Language = 'en',
  [switch]$Fullscreen,
  [int]$StartAt = 1,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$studyDir   = Split-Path $PSScriptRoot -Parent
$Study      = Split-Path $studyDir -Leaf
$ordersFile = Join-Path $studyDir 'counterbalance\task-orders.csv'

# PEBL workspace: first parent of the study with settings/launcher.cfg
$workspaceDir = Split-Path $studyDir -Parent
while ($workspaceDir -and -not (Test-Path (Join-Path $workspaceDir 'settings\launcher.cfg'))) {
  $workspaceDir = Split-Path $workspaceDir -Parent
}

# pebl2.exe: from the launcher settings, else the default install folder
$pebl = 'C:\Program Files (x86)\PEBL2\bin\pebl2.exe'
if ($workspaceDir) {
  $cfg = Join-Path $workspaceDir 'settings\launcher.cfg'
  $line = Select-String -Path $cfg -Pattern '^pebl_executable_path=(.+)$' | Select-Object -First 1
  if ($line) { $pebl = $line.Matches[0].Groups[1].Value.Trim() }
}
if (-not $DryRun -and -not (Test-Path $pebl)) { throw "pebl2.exe not found at $pebl" }
if (-not (Test-Path $ordersFile)) { throw "$ordersFile not found. Run utils\make-counterbalance-orders.ps1 first." }

$orders = @{}
foreach ($row in (Import-Csv $ordersFile)) { $orders[$row.participant_code] = $row }
$taskCols = @((Get-Content $ordersFile -TotalCount 1).Split(',') | Select-Object -Skip 1)
$first = (Import-Csv $ordersFile | Select-Object -First 1).participant_code
$prefix = $first.Split('_')[0]
$width  = $first.Split('_')[1].Length
$codeRx = '^' + [regex]::Escape($prefix) + '_\d{' + $width + '}$'
$range  = '{0}_{1} to {0}_{2}' -f $prefix, ('1'.PadLeft($width, '0')), "$($orders.Count)".PadLeft($width, '0')

# Ask until the code is valid
while ($true) {
  if (-not $Participant) { $Participant = Read-Host "Participant code ($range)" }
  $Participant = $Participant.Trim().ToUpper()
  if ($Participant -match $codeRx -and $orders.ContainsKey($Participant)) { break }
  Write-Host "  '$Participant' is not a valid code. Use $range." -ForegroundColor Yellow
  $Participant = $null
}

$tests = @($taskCols | ForEach-Object { $orders[$Participant].$_ })
if ($StartAt -lt 1 -or $StartAt -gt $tests.Count) { throw "-StartAt must be between 1 and $($tests.Count)." }

# Chain file in the launcher's format
$chain = [ordered]@{
  chain_name      = $Participant
  description     = "Counterbalanced order for $Participant (from counterbalance/task-orders.csv)"
  items           = @($tests | ForEach-Object {
    [ordered]@{ item_type = 'test'; language = $Language; param_variant = 'default'; random_group = 0; test_name = $_ }
  })
  lsl_enabled     = $false
  lsl_stream_name = 'PEBL_{test}'
  upload_enabled  = $false
}
$chainFile = Join-Path $studyDir "chains\$Participant.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($chainFile, ($chain | ConvertTo-Json -Depth 5), $utf8NoBom)

# Test name -> .pbl file: "tol/TOL" -> tests/tol/TOL.pbl, "maze" -> tests/maze/maze.pbl
function Get-TestFile($name) {
  $parts = $name.Split('/')
  if ($parts.Count -eq 2) { return Join-Path $studyDir "tests\$($parts[0])\$($parts[1]).pbl" }
  return Join-Path $studyDir "tests\$name\$name.pbl"
}
foreach ($t in $tests) {
  if (-not (Test-Path (Get-TestFile $t))) { throw "Test file not found: $(Get-TestFile $t)" }
}

Write-Host ""
Write-Host "Participant $Participant  ($Study, chain: chains\$Participant.json)"
for ($i = 0; $i -lt $tests.Count; $i++) {
  $mark = if ($i + 1 -lt $StartAt) { ' (skipped)' } else { '' }
  Write-Host ("  {0}. {1}{2}" -f ($i + 1), $tests[$i], $mark)
}
Write-Host ""

$log = if ($workspaceDir) { Join-Path $workspaceDir 'logs\launcher-log.csv' } else { $null }

# Asks what to do before test $i (or, with $i = number of tests, before
# finishing). Returns 'go', 'back' or 'quit'.
function Read-NextStep($i) {
  while ($true) {
    Write-Host ""
    if ($i -lt $tests.Count) {
      Write-Host ("Next: [{0}/{1}] {2}" -f ($i + 1), $tests.Count, $tests[$i]) -ForegroundColor Cyan
      $help = '  Enter = start it'
    } else {
      Write-Host "All $($tests.Count) tests done." -ForegroundColor Cyan
      $help = '  Enter = finish'
    }
    if ($i -gt 0) { $help += "   b = go back to the previous test ($($tests[$i - 1]))" }
    $help += '   q = quit'
    Write-Host $help
    $answer = "$(Read-Host '  >')".Trim().ToLower()
    if ($answer -eq '') { return 'go' }
    if ($answer -eq 'b' -or $answer -eq 'back') {
      if ($i -gt 0) { return 'back' }
      Write-Host '  This is the first test; there is no previous one.' -ForegroundColor Yellow
    } elseif ($answer -eq 'q' -or $answer -eq 'quit') {
      return 'quit'
    } else {
      Write-Host "  Unknown command '$answer'. Type b, q, or just press Enter." -ForegroundColor Yellow
    }
  }
}

# Each run of a test (also a repeated one) is logged; tests write their data to
# tests/<test>/data/<code>/ again, so check which files belong to the repeat.
$i = $StartAt - 1
while ($true) {
  if (-not $DryRun) {
    $step = Read-NextStep $i
    if ($step -eq 'back') { $i--; continue }
    if ($step -eq 'quit') {
      Write-Host ""
      Write-Host "Stopped before test $($i + 1) of $($tests.Count). To continue later:" -ForegroundColor Yellow
      Write-Host "  run-participant.bat -Participant $Participant -StartAt $($i + 1)"
      return
    }
  }
  if ($i -ge $tests.Count) { break }

  $item = $chain.items[$i]
  $file = Get-TestFile $item.test_name
  $peblArgs = @("`"$file`"", '-s', $Participant, '--language', $item.language)
  if ($item.param_variant -ne 'default') { $peblArgs += @('--pfile', "params/$($item.param_variant).par.json") }
  if ($Fullscreen) { $peblArgs += '--fullscreen' }

  Write-Host ("[{0}/{1}] {2}" -f ($i + 1), $tests.Count, $item.test_name)
  if ($DryRun) { Write-Host "  cd `"$(Split-Path $file -Parent)`"; & `"$pebl`" $($peblArgs -join ' ')"; $i++; continue }

  $start = Get-Date
  $p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory (Split-Path $file -Parent) -Wait -PassThru
  $secs = [int]((Get-Date) - $start).TotalSeconds
  Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

  $fs = if ($Fullscreen) { 'true' } else { 'false' }
  $entry = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $file, $Participant, $item.language, $fs, $p.ExitCode, $secs
  if ($log) { [IO.File]::AppendAllText($log, "$entry`r`n", $utf8NoBom) }
  $i++
}

Write-Host ""
if ($DryRun) { Write-Host 'Dry run: nothing was launched.' } else { Write-Host "All tests done for $Participant." }
