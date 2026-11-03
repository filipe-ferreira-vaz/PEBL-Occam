# PROOF OF CONCEPT: runs all tests of this study for one participant in
# alphabetical order, with the affect grid before the first test and after
# every test:  affectgrid, bigfive, affectgrid, maze, affectgrid, ... affectgrid
# The order is written to chains/AffectAlternating.json (also usable in the
# PEBL launcher) and then run like run-participant.bat runs a chain.
#
# Usage: double-click run-affect-chain.bat in the study folder, or
#   run-affect-chain.bat -Participant PART_0042 -Fullscreen
#   run-affect-chain.bat -Participant PART_0042 -StartAt 5   (resume after a crash)
#   run-affect-chain.bat -Participant PART_0042 -DryRun      (print the commands, run nothing)
#
# affectgrid runs several times under the same participant code. From its 2nd
# run on, PEBL asks "Choose new code / Add Session": click "Add Session" so the
# ratings are appended to the same affectgrid file (each row has a timestamp).
#
# Each test runs like the PEBL launcher runs it:
#   pebl2.exe tests/<test>/<test>.pbl -s <code> --language <lang> [--fullscreen]
# from the test's folder, so data goes to tests/<test>/data/<code>/. A row per
# test is added to logs/launcher-log.csv of the PEBL workspace (the first
# parent folder with settings/launcher.cfg), if there is one.
#
# Before each test (and after the last one) it waits for a command:
#   Enter  start the next test (or finish)
#   b      go back to the previous test, e.g. if its window was closed by
#          accident (type b again to go back further)
#   q      quit (prints the -StartAt command to continue later)

param(
  [string]$Participant,
  [string]$Language = 'en',
  [switch]$Fullscreen,
  [int]$StartAt = 1,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$studyDir  = Split-Path $PSScriptRoot -Parent
$Study     = Split-Path $studyDir -Leaf
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

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
if (-not $DryRun -and -not (Test-Path $pebl)) { throw "pebl2.exe not found at $pebl" }

# Tests in tests/, alphabetical (the .pbl of a folder is the one named like the
# folder, otherwise its only .pbl); "tol/TOL" style names like the launcher's
$names = @()
foreach ($dir in (Get-ChildItem -Path (Join-Path $studyDir 'tests') -Directory | Sort-Object { $_.Name.ToLower() })) {
  $pbls = @(Get-ChildItem -Path $dir.FullName -Filter *.pbl -File)
  $pbl = $pbls | Where-Object { $_.BaseName -eq $dir.Name } | Select-Object -First 1
  if (-not $pbl -and $pbls.Count -eq 1) { $pbl = $pbls[0] }
  if (-not $pbl) { continue }
  $names += $(if ($pbl.BaseName -ceq $dir.Name) { $dir.Name } else { "$($dir.Name)/$($pbl.BaseName)" })
}
if (-not ($names -contains 'affectgrid')) { throw "This study has no affectgrid test." }
$others = @($names | Where-Object { $_ -ne 'affectgrid' })
$order = @('affectgrid')
foreach ($t in $others) { $order += $t; $order += 'affectgrid' }

# Chain file in the launcher's format
$itemsJson = ($order | ForEach-Object {
  "    {`r`n      `"item_type`": `"test`",`r`n      `"language`": `"$Language`",`r`n      `"param_variant`": `"default`",`r`n      `"random_group`": 0,`r`n      `"test_name`": `"$_`"`r`n    }"
}) -join ",`r`n"
$chainFile = Join-Path $studyDir 'chains\AffectAlternating.json'
New-Item -ItemType Directory -Force -Path (Split-Path $chainFile -Parent) | Out-Null
[IO.File]::WriteAllText($chainFile, "{`r`n  `"chain_name`": `"AffectAlternating`",`r`n  `"description`": `"All tests in alphabetical order, alternating with affectgrid (proof of concept)`",`r`n  `"items`": [`r`n$itemsJson`r`n  ],`r`n  `"lsl_enabled`": false,`r`n  `"lsl_stream_name`": `"PEBL_{test}`",`r`n  `"upload_enabled`": false`r`n}`r`n", $utf8NoBom)

# Participant code: listed in counterbalance\task-orders.csv if the study has one, else any CODE_1234
$ordersFile = Join-Path $studyDir 'counterbalance\task-orders.csv'
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

$chain = Get-Content $chainFile -Raw | ConvertFrom-Json
$items = @($chain.items | Where-Object { $_.item_type -eq 'test' })
if ($StartAt -lt 1 -or $StartAt -gt $items.Count) { throw "-StartAt must be between 1 and $($items.Count)." }

# Test name -> .pbl file: "tol/TOL" -> tests/tol/TOL.pbl, "maze" -> tests/maze/maze.pbl
function Get-TestFile($name) {
  $parts = $name.Split('/')
  if ($parts.Count -eq 2) { return Join-Path $studyDir "tests\$($parts[0])\$($parts[1]).pbl" }
  return Join-Path $studyDir "tests\$name\$name.pbl"
}
foreach ($item in $items) {
  if (-not (Test-Path (Get-TestFile $item.test_name))) { throw "Test file not found: $(Get-TestFile $item.test_name)" }
}

Write-Host ""
Write-Host "Participant $Participant  ($Study, chain: chains\AffectAlternating.json)"
for ($i = 0; $i -lt $items.Count; $i++) {
  $mark = if ($i + 1 -lt $StartAt) { ' (skipped)' } else { '' }
  Write-Host ("  {0}. {1}{2}" -f ($i + 1), $items[$i].test_name, $mark)
}
Write-Host ""

$log = if ($workspaceDir) { Join-Path $workspaceDir 'logs\launcher-log.csv' } else { $null }

# Asks what to do before test $i (or, with $i = number of tests, before
# finishing). Returns 'go', 'back' or 'quit'.
function Read-NextStep($i) {
  while ($true) {
    Write-Host ""
    if ($i -lt $items.Count) {
      Write-Host ("Next: [{0}/{1}] {2}" -f ($i + 1), $items.Count, $items[$i].test_name) -ForegroundColor Cyan
      $help = '  Enter = start it'
    } else {
      Write-Host "All $($items.Count) tests done." -ForegroundColor Cyan
      $help = '  Enter = finish'
    }
    if ($i -gt 0) { $help += "   b = go back to the previous test ($($items[$i - 1].test_name))" }
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
      Write-Host "Stopped before test $($i + 1) of $($items.Count). To continue later:" -ForegroundColor Yellow
      Write-Host "  run-affect-chain.bat -Participant $Participant -StartAt $($i + 1)"
      return
    }
  }
  if ($i -ge $items.Count) { break }

  $item = $items[$i]
  $file = Get-TestFile $item.test_name
  $peblArgs = @("`"$file`"", '-s', $Participant, '--language', $item.language)
  if ($item.param_variant -and $item.param_variant -ne 'default') { $peblArgs += @('--pfile', "params/$($item.param_variant).par.json") }
  if ($Fullscreen) { $peblArgs += '--fullscreen' }

  Write-Host ("[{0}/{1}] {2}" -f ($i + 1), $items.Count, $item.test_name)
  if ($DryRun) { Write-Host "  cd `"$(Split-Path $file -Parent)`"; & `"$pebl`" $($peblArgs -join ' ')"; $i++; continue }

  $start = Get-Date
  $p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory (Split-Path $file -Parent) -Wait -PassThru
  $secs = [int]((Get-Date) - $start).TotalSeconds
  Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

  if ($log) {
    $fs = if ($Fullscreen) { 'true' } else { 'false' }
    $entry = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $file, $Participant, $item.language, $fs, $p.ExitCode, $secs
    [IO.File]::AppendAllText($log, "$entry`r`n", $utf8NoBom)
  }
  $i++
}

Write-Host ""
if ($DryRun) { Write-Host 'Dry run: nothing was launched.' } else { Write-Host "All tests done for $Participant." }
