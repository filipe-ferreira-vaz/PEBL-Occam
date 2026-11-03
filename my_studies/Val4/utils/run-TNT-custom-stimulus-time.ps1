# Runs the TNT-custom-stimulus-time test for one participant with a
# stimulus duration typed in the terminal.
#
# Usage: double-click run-TNT-custom-stimulus-time.bat in the study folder, or
#   run-TNT-custom-stimulus-time.bat -Participant PART_0042 -Fullscreen
#   run-TNT-custom-stimulus-time.bat -Participant PART_0042 -Language pt
#
# It asks for the participant code, then for
#   StimulusDuration  presentation time of each stimulus in ms, e.g. 2500
# (Enter = keep the default shown in parentheses, read from the test's
# params/TNT-custom-stimulus-time.pbl.schema.json). The value is written to
# tests/TNT-custom-stimulus-time/params/custom.par.json and the test runs like
#   pebl2.exe tests/TNT-custom-stimulus-time/TNT-custom-stimulus-time.pbl -s <code> --language <lang> --pfile custom.par.json [--fullscreen]
# (pebl2 looks for the --pfile file in the test's params/ folder)
# from the test's folder, so data goes to tests/TNT-custom-stimulus-time/data/<code>/.
# A row is added to logs/launcher-log.csv of the PEBL workspace, if there is one.

param(
  [string]$Participant,
  [string]$Language = 'en',
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$testName   = 'TNT-custom-stimulus-time'
$studyDir   = Split-Path $PSScriptRoot -Parent
$testDir    = Join-Path $studyDir "tests\$testName"
$testFile   = Join-Path $testDir "$testName.pbl"
$parFile    = Join-Path $testDir 'params\custom.par.json'
$schemaFile = Join-Path $testDir "params\$testName.pbl.schema.json"
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

# Default stimulus duration: from the test's schema, else 2500 ms
$defaultDuration = 2500
if (Test-Path $schemaFile) {
  $schema = [IO.File]::ReadAllText($schemaFile) | ConvertFrom-Json
  $entry = $schema.parameters | Where-Object { $_.name -eq 'StimulusDuration' } | Select-Object -First 1
  if ($entry) { $defaultDuration = [int]$entry.default }
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

# Asks for one whole number >= $min; Enter = $default
function Read-Int([string]$prompt, [int]$default, [int]$min) {
  while ($true) {
    $answer = "$(Read-Host "$prompt ($default)")".Trim()
    if (-not $answer) { return $default }
    $n = 0
    if ([int]::TryParse($answer, [ref]$n) -and $n -ge $min) { return $n }
    Write-Host "  Type a whole number of at least $min, e.g. $default." -ForegroundColor Yellow
  }
}

Write-Host ""
$duration = Read-Int 'Stimulus duration in ms' $defaultDuration 1

$json = "{`r`n  `"StimulusDuration`": $duration`r`n}`r`n"
[IO.File]::WriteAllText($parFile, $json, $utf8NoBom)

$peblArgs = @("`"$testFile`"", '-s', $Participant, '--language', $Language, '--pfile', 'custom.par.json')
if ($Fullscreen) { $peblArgs += '--fullscreen' }
Write-Host ""
Write-Host "Running $testName (StimulusDuration $duration ms)..."
$start = Get-Date
$p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory $testDir -Wait -PassThru
$secs = [int]((Get-Date) - $start).TotalSeconds
Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

if ($log) {
  $fs = if ($Fullscreen) { 'true' } else { 'false' }
  $row = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $testFile, $Participant, $Language, $fs, $p.ExitCode, $secs
  [IO.File]::AppendAllText($log, "$row`r`n", $utf8NoBom)
}
