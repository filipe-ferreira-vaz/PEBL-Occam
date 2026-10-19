# Runs single tests of this study for one participant, picked from a menu.
# Use it to run (or re-run) one test outside the counterbalanced chain.
#
# Usage: double-click run-test.bat in the study folder, or
#   run-test.bat -Participant PART_0042 -Fullscreen
#   run-test.bat -Participant PART_0042 -Language pt
#
# It asks for the participant code (data is saved under it), then lists every
# test in tests/:
#   number  run that test, then come back to the list
#   q       quit
# Tests that already have data for this participant are marked "(has data)".
#
# Tests are the folders in tests/, sorted by name; the .pbl file of a folder is
# the one named like the folder (any case), otherwise its only .pbl file.
# Each test runs like the PEBL launcher runs it:
#   pebl2.exe tests/<test>/<test>.pbl -s <code> --language <lang> [--fullscreen]
# from the test's folder, so data goes to tests/<test>/data/<code>/. A row per
# run is added to logs/launcher-log.csv of the PEBL workspace (the first parent
# folder with settings/launcher.cfg), if there is one.

param(
  [string]$Participant,
  [string]$Language = 'en',
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$studyDir   = Split-Path $PSScriptRoot -Parent
$Study      = Split-Path $studyDir -Leaf
$testsDir   = Join-Path $studyDir 'tests'
$ordersFile = Join-Path $studyDir 'counterbalance\task-orders.csv'
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

# Tests in tests/
if (-not (Test-Path $testsDir)) { throw "No tests folder in $studyDir." }
$tests = @()
foreach ($dir in (Get-ChildItem -Path $testsDir -Directory | Sort-Object Name)) {
  $pbls = @(Get-ChildItem -Path $dir.FullName -Filter *.pbl -File)
  $pbl = $pbls | Where-Object { $_.BaseName -eq $dir.Name } | Select-Object -First 1
  if (-not $pbl -and $pbls.Count -eq 1) { $pbl = $pbls[0] }
  if (-not $pbl) { continue }
  $name = if ($pbl.BaseName -ceq $dir.Name) { $dir.Name } else { "$($dir.Name)/$($pbl.BaseName)" }
  $tests += [pscustomobject]@{ Name = $name; File = $pbl.FullName; Dir = $dir.FullName }
}
if ($tests.Count -eq 0) { throw "No tests found in $testsDir." }

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

while ($true) {
  Write-Host ""
  Write-Host "Participant $Participant  ($Study): choose a test" -ForegroundColor Cyan
  for ($i = 0; $i -lt $tests.Count; $i++) {
    $hasData = Test-Path (Join-Path $tests[$i].Dir "data\$Participant")
    $mark = if ($hasData) { '  (has data)' } else { '' }
    Write-Host ("  {0,2}. {1}{2}" -f ($i + 1), $tests[$i].Name, $mark)
  }
  Write-Host "  1-$($tests.Count) = run that test   q = quit"
  $answer = "$(Read-Host '  >')".Trim().ToLower()

  if ($answer -eq 'q' -or $answer -eq 'quit') { break }
  $num = 0
  if (-not [int]::TryParse($answer, [ref]$num) -or $num -lt 1 -or $num -gt $tests.Count) {
    Write-Host "  Unknown choice '$answer'. Type a number from 1 to $($tests.Count), or q." -ForegroundColor Yellow
    continue
  }

  $t = $tests[$num - 1]
  $peblArgs = @("`"$($t.File)`"", '-s', $Participant, '--language', $Language)
  if ($Fullscreen) { $peblArgs += '--fullscreen' }
  Write-Host ""
  Write-Host "Running $($t.Name)..."
  $start = Get-Date
  $p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory $t.Dir -Wait -PassThru
  $secs = [int]((Get-Date) - $start).TotalSeconds
  Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

  if ($log) {
    $fs = if ($Fullscreen) { 'true' } else { 'false' }
    $entry = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $t.File, $Participant, $Language, $fs, $p.ExitCode, $secs
    [IO.File]::AppendAllText($log, "$entry`r`n", $utf8NoBom)
  }
}

Write-Host ""
Write-Host "Done."