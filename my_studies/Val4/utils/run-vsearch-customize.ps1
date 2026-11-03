# Runs the vsearch-customize test for one participant with search sizes,
# numbers of targets and search box size typed in the terminal.
#
# Usage: double-click run-vsearch-customize.bat in the study folder, or
#   run-vsearch-customize.bat -Participant PART_0042 -Fullscreen
#   run-vsearch-customize.bat -Participant PART_0042 -Language pt
#
# It asks for the participant code, then for
#   searchsizes  number of items in the search display, e.g. 10,20,30
#   numtargs     number of targets per display, e.g. 0,1,5
#   boxwidth     width of the search box in pixels, e.g. 600
#   boxheight    height of the search box in pixels, e.g. 400
# (Enter = keep the default shown in parentheses). Every size is crossed with
# every number of targets. The values are written to
# tests/vsearch-customize/params/custom.par.json and the test runs like
#   pebl2.exe tests/vsearch-customize/vsearch-customize.pbl -s <code> --language <lang> --pfile custom.par.json [--fullscreen]
# (pebl2 looks for the --pfile file in the test's params/ folder)
# from the test's folder, so data goes to tests/vsearch-customize/data/<code>/.
# A row is added to logs/launcher-log.csv of the PEBL workspace, if there is one.

param(
  [string]$Participant,
  [string]$Language = 'en',
  [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'
$studyDir   = Split-Path $PSScriptRoot -Parent
$testDir    = Join-Path $studyDir 'tests\vsearch-customize'
$testFile   = Join-Path $testDir 'vsearch-customize.pbl'
$parFile    = Join-Path $testDir 'params\custom.par.json'
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

# Asks for a comma-separated list of whole numbers >= $min; Enter = $default
function Read-IntList([string]$prompt, [int[]]$default, [int]$min) {
  while ($true) {
    $answer = "$(Read-Host "$prompt ($($default -join ','))")".Trim()
    if (-not $answer) { return $default }
    $values = @()
    $ok = $true
    foreach ($part in $answer.Split(',')) {
      $n = 0
      if ([int]::TryParse($part.Trim(), [ref]$n) -and $n -ge $min) { $values += $n } else { $ok = $false }
    }
    if ($ok) { return $values }
    Write-Host "  Type whole numbers of at least $min separated by commas, e.g. $($default -join ',')." -ForegroundColor Yellow
  }
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
while ($true) {
  $searchsizes = @(Read-IntList 'Search sizes, separated by commas' @(10, 20, 30) 1)
  $numtargs    = @(Read-IntList 'Numbers of targets, separated by commas' @(0, 1, 5) 0)
  # every size is crossed with every number of targets, so no display may have more targets than items
  $smallest = ($searchsizes | Measure-Object -Minimum).Minimum
  $largest  = ($numtargs | Measure-Object -Maximum).Maximum
  if ($largest -le $smallest) { break }
  Write-Host "  $largest targets do not fit in a search size of $smallest. Enter the values again." -ForegroundColor Yellow
}
$boxwidth  = Read-Int 'Search box width in pixels' 600 1
$boxheight = Read-Int 'Search box height in pixels' 400 1

$json = "{`r`n  `"searchsizes`": [$($searchsizes -join ',')],`r`n  `"numtargs`": [$($numtargs -join ',')],`r`n  `"boxwidth`": $boxwidth,`r`n  `"boxheight`": $boxheight`r`n}`r`n"
[IO.File]::WriteAllText($parFile, $json, $utf8NoBom)

$peblArgs = @("`"$testFile`"", '-s', $Participant, '--language', $Language, '--pfile', 'custom.par.json')
if ($Fullscreen) { $peblArgs += '--fullscreen' }
Write-Host ""
Write-Host "Running vsearch-customize (searchsizes $($searchsizes -join ','), numtargs $($numtargs -join ','), box $boxwidth x $boxheight)..."
$start = Get-Date
$p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory $testDir -Wait -PassThru
$secs = [int]((Get-Date) - $start).TotalSeconds
Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

if ($log) {
  $fs = if ($Fullscreen) { 'true' } else { 'false' }
  $entry = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $testFile, $Participant, $Language, $fs, $p.ExitCode, $secs
  [IO.File]::AppendAllText($log, "$entry`r`n", $utf8NoBom)
}
