<# : batch part (cmd runs these lines; PowerShell skips them as a comment)
@echo off
setlocal
set "STUDY_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText('%~f0'))) %*"
echo.
pause
exit /b
#>

# setup-study.bat -- one-file setup for counterbalanced PEBL studies.
#
# Drop this file into a study folder (my_studies/<Study>, next to its tests
# folder) and double-click it. It:
#   1. writes utils/beeps.pbl (if missing) and adds the beeps library plus the
#      standard start/end beeps to every test in tests/ (same as sync-beeps.ps1:
#      BeepsStart() after InitializeLSL(...), BeepsEnd() before FinalizeLSL())
#   2. makes one counterbalanced chain per possible test order
#      (N tests -> N! chains): counterbalance/chains/PART_0001.json ...
#   3. writes the participant order file counterbalance/task-orders.csv
#      (participant_code,task1,...,taskN)
#   4. writes run-participant.bat (+ utils/run-participant.ps1), which asks for
#      a participant code and runs that participant's chain
#
# Tests are the folders in tests/, sorted by name. The .pbl file of a folder is
# the one named like the folder (any case; tol/TOL.pbl -> test "tol/TOL"),
# otherwise its only .pbl file.
#
# Counterbalancing: rotating an order (abcdefg -> bcdefga -> ...) splits all
# N! orders into (N-1)! groups of N; each group is a Latin square (every test
# once in every position). Groups, and rows inside each group, are shuffled
# with a fixed seed and then numbered, so every block of N consecutive codes
# is position-balanced and all codes together use every order exactly once.
#
# Running it again is safe: beeps are only refreshed, and an existing
# task-orders.csv for the same tests is kept (orders already handed out stay
# the same). If the tests changed, it stops unless -Force is given.
#
# Options (from a command prompt in the study folder):
#   setup-study.bat -Force            regenerate the orders even if tests changed
#   setup-study.bat -Prefix SUBJ      code prefix (default PART -> PART_0001)
#   setup-study.bat -Seed 123         another (reproducible) shuffle
#   setup-study.bat -Language pt      language written into the chains (default en)
# To keep a test silent, put this line in it:  ## beeps: no auto calls

param(
  [string]$Prefix = 'PART',
  [int]$Seed = 20261014,
  [string]$Language = 'en',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------- embedded files
# utils/beeps.pbl: written only if missing (edit the study's copy, then re-run
# setup-study.bat to copy it into the tests again)
$beepsPbl = @'
##########################################################
## beeps.pbl -- reusable pure-tone (sine wave) functions
##
## PEBL has no import statement, so this file is COPIED into each test
## by setup-study.bat (from <study>/utils/beeps.pbl). Edit only that copy,
## then re-run setup-study.bat.
##
## Standard start/end beeps: setup-study.bat also inserts
##     BeepsStart()   right after the test's LSL setup line (window just opened)
##     BeepsEnd()     right before the test's LSL shutdown line (test finished)
## so every synced test beeps at its start and end automatically. BeepsEnd()
## also saves all beeps to data/<subject>/beeps-<subject>.csv.
## To opt a test out of the automatic calls, put this line anywhere in it:
##     ## beeps: no auto calls
## (the functions below stay available for calling by hand).
##
## Why not MakeSineWave()?  In this PEBL build (2.4, Windows) MakeSineWave()
## returns a sound with no audio buffer: it plays for 0 ms. Instead, each
## tone is written once to a .wav file (via a small PowerShell helper) in the
## test's folder, e.g. tone-1000Hz-50ms-a0.8.wav, and loaded with LoadSound().
## Later runs reuse the cached file, so the PowerShell call only happens the
## first time a given frequency/duration/amplitude is requested.
##
## Functions:
##   MakeTone(freq, durationMs, amplitude:0.8)
##        Returns a sound object you can pass to PlayTone/PlayBackground.
##        Call it early (e.g. during setup) to avoid the one-time ~0.3 s
##        generation delay and the up-to-1 s clock sync (see below) at
##        play time.
##   PlayTone(freq:1000, durationMs:50, amplitude:0.8, blocking:0, label:"tone")
##        Plays a tone and returns its onset timestamp (GetTime(), ms).
##        blocking=1 waits for the tone to finish (use it right before the
##        script exits). Each play is recorded in gToneLog.
##   Beep(label:"beep")
##        Shortcut: 1000 Hz, 50 ms, amplitude 0.8, non-blocking.
##   BeepsStart() / BeepsEnd()
##        Standard 1000 Hz / 50 ms start and end beeps (see above). The end
##        beep is blocking, so it finishes before the test closes.
##   GetToneLog()
##        List of [label, freq, durationMs, amplitude, timestamp, clocktime]
##        for every tone played so far.
##
## timestamp comes from GetTime(), so it is on the same clock as the RTs and
## abstime values PEBL tests already record.
## clocktime is the PC's local clock time, "YYYY-MM-DD HH:MM:SS.mmm".
## PEBL's TimeStamp() only has 1 s resolution (and GetTimeOfDay() returns a
## broken value in this build), so on first use the library waits for the PC
## clock's second to tick over (up to 1 s), records GetTime() at that instant,
## and afterwards computes clock time = that second + elapsed GetTime().
##########################################################

define MakeTone(freq, durationMs, amplitude:0.8)
{
  ToneClockSync()
  key <- freq + "Hz-" + durationMs + "ms-a" + amplitude

  ## reuse an already-loaded sound
  if(not VariableExists("gToneCache"))
  {
    gToneCache <- []
  }
  sound <- 0
  loop(pair, gToneCache)
  {
    if(First(pair) == key)
    {
      sound <- Second(pair)
    }
  }

  if(IsNumber(sound))
  {
    filename <- "tone-" + key + ".wav"
    if(not FileExists(filename))
    {
      ToneWriteHelper()
      cmd <- "powershell -NoProfile -ExecutionPolicy Bypass -File beeps-maketone.ps1" +
             " -f " + freq + " -d " + durationMs + " -a " + amplitude + " -o " + filename
      SystemCall(cmd, "")
      if(not FileExists(filename))
      {
        SignalFatalError("beeps.pbl: could not create " + filename +
                         " (PowerShell is required to generate tones)")
      }
    }
    sound <- LoadSound(filename)
    gToneCache <- Append(gToneCache, [key, sound])
  }
  return(sound)
}


define PlayTone(freq:1000, durationMs:50, amplitude:0.8, blocking:0, label:"tone")
{
  sound <- MakeTone(freq, durationMs, amplitude)
  if(not VariableExists("gToneLog"))
  {
    gToneLog <- []
  }

  t <- GetTime()
  if(blocking)
  {
    PlayForeground(sound)
  } else {
    PlayBackground(sound)
  }

  gToneLog <- Append(gToneLog, [label, freq, durationMs, amplitude, t, ToneClockTime(t)])
  return(t)
}


define Beep(label:"beep")
{
  return(PlayTone(1000, 50, 0.8, 0, label))
}


## Syncs GetTime() to the PC clock once (waits up to 1 s the first time).
## Returns [GetTime() at a whole second, that second as ms since midnight].
define ToneClockSync()
{
  if(not VariableExists("gToneClockAnchor"))
  {
    ts0 <- TimeStamp()
    ts <- ts0
    while(ts == ts0)
    {
      ts <- TimeStamp()
    }
    t <- GetTime()
    gToneClockAnchor <- [t, Nth(ToneParseTimeStamp(ts),4)*1000]
  }
  return(gToneClockAnchor)
}


## Converts a GetTime() value to PC local clock time "YYYY-MM-DD HH:MM:SS.mmm"
define ToneClockTime(t)
{
  anchor <- ToneClockSync()
  date <- ToneParseTimeStamp(TimeStamp())
  ms <- Mod(Second(anchor) + t - First(anchor), 86400000)
  clock <- Nth(date,1) + "-" + ZeroPad(Nth(date,2),2) + "-" + ZeroPad(Nth(date,3),2) + " " +
           ZeroPad(Floor(ms/3600000),2) + ":" + ZeroPad(Floor(Mod(ms,3600000)/60000),2) + ":" +
           ZeroPad(Floor(Mod(ms,60000)/1000),2) + "." + ZeroPad(Mod(ms,1000),3)
  return(clock)
}


## Parses TimeStamp() text like "Fri Oct 09 20:31:36 2026"
## into [year, month, day, seconds since midnight]
define ToneParseTimeStamp(ts)
{
  tokens <- []
  loop(tok, SplitString(ts, " "))
  {
    if(tok != "")
    {
      tokens <- Append(tokens, tok)
    }
  }
  month <- 1
  i <- 1
  loop(name, ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"])
  {
    if(name == Nth(tokens,2))
    {
      month <- i
    }
    i <- i + 1
  }
  hms <- SplitString(Nth(tokens,4), ":")
  secs <- ToNumber(Nth(hms,1))*3600 + ToNumber(Nth(hms,2))*60 + ToNumber(Nth(hms,3))
  return([ToNumber(Nth(tokens,5)), month, ToNumber(Nth(tokens,3)), secs])
}


## Standard start beep (inserted automatically by setup-study.bat)
define BeepsStart()
{
  MakeTone(1000, 50)   ## generate/load and sync the clock before playing
  return(Beep("beep_start"))
}


## Standard end beep (inserted automatically by setup-study.bat).
## Blocking, then saves every beep of this run to data/<subject>/beeps-<subject>.csv
define BeepsEnd()
{
  t <- PlayTone(1000, 50, 0.8, 1, "beep_end")
  BeepsWriteLog()
  return(t)
}


## Writes all beeps played so far to data/<subject>/beeps-<subject>.csv
## (the same folder as the test's other data files; appends if it exists)
define BeepsWriteLog()
{
  dir <- "data/" + gSubNum
  if(not IsDirectory("data"))
  {
    MakeDirectory("data")
  }
  if(not IsDirectory(dir))
  {
    MakeDirectory(dir)
  }
  filename <- dir + "/beeps-" + gSubNum + ".csv"
  isnew <- not FileExists(filename)
  out <- FileOpenAppend(filename)
  if(isnew)
  {
    FilePrint(out, "subnum,event,freq,durationms,amplitude,abstime,clocktime")
  }
  loop(tone, GetToneLog())
  {
    FilePrint(out, gSubNum + "," + ConcatenateList(tone, ","))
  }
  FileClose(out)
  return(filename)
}


define GetToneLog()
{
  if(not VariableExists("gToneLog"))
  {
    gToneLog <- []
  }
  return(gToneLog)
}


## Writes the PowerShell WAV generator next to the test (once).
## Output: 44.1 kHz, 16-bit, mono PCM sine wave.
define ToneWriteHelper()
{
  helper <- "beeps-maketone.ps1"
  if(not FileExists(helper))
  {
    ps <- FileOpenOverwrite(helper)
    FilePrint(ps, "param([double]$f,[int]$d,[double]$a,[string]$o)")
    FilePrint(ps, "$sr=44100; $n=[int]($sr*$d/1000); $ms=New-Object IO.MemoryStream; $w=New-Object IO.BinaryWriter($ms)")
    FilePrint(ps, "$w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36+$n*2)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))")
    FilePrint(ps, "$w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$sr); $w.Write([int]($sr*2)); $w.Write([int16]2); $w.Write([int16]16)")
    FilePrint(ps, "$w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]($n*2))")
    FilePrint(ps, "for($i=0;$i -lt $n;$i++){ $w.Write([int16][Math]::Round(32767*$a*[Math]::Sin(2*[Math]::PI*$f*$i/$sr))) }")
    FilePrint(ps, "$w.Flush(); [IO.File]::WriteAllBytes((Join-Path (Get-Location) $o),$ms.ToArray())")
    FileClose(ps)
  }
  return(helper)
}
'@

# utils/run-participant.ps1: rewritten on every run
$runnerPs1 = @'
# Runs this study's tests for one participant, in the order of that
# participant's counterbalanced chain (counterbalance/chains/<code>.json).
# Generated by setup-study.bat -- re-running it overwrites this file.
#
# Usage: double-click run-participant.bat in the study folder, or
#   run-participant.bat -Participant PART_0042 -Fullscreen
#   run-participant.bat -Participant PART_0042 -StartAt 4   (resume after a crash: skip tests 1-3)
#   run-participant.bat -Participant PART_0042 -DryRun      (print the commands, run nothing)
#
# Each test runs like the PEBL launcher runs it:
#   pebl2.exe tests/<test>/<test>.pbl -s <code> --language <lang> [--pfile ...] [--fullscreen]
# from the test's folder, so data goes to tests/<test>/data/<code>/. A row per
# test is added to logs/launcher-log.csv of the PEBL workspace (the first
# parent folder with settings/launcher.cfg), if there is one.

param(
  [string]$Participant,
  [switch]$Fullscreen,
  [int]$StartAt = 1,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$studyDir  = Split-Path $PSScriptRoot -Parent
$Study     = Split-Path $studyDir -Leaf
$chainsDir = Join-Path $studyDir 'counterbalance\chains'
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

$chainFiles = @(Get-ChildItem -Path $chainsDir -Filter *.json -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($chainFiles.Count -eq 0) { throw "No chains in $chainsDir. Run setup-study.bat first." }
$range = "$($chainFiles[0].BaseName) to $($chainFiles[-1].BaseName)"

# Ask until the code is valid
while ($true) {
  if (-not $Participant) { $Participant = Read-Host "Participant code ($range)" }
  $Participant = $Participant.Trim().ToUpper()
  $chainFile = Join-Path $chainsDir "$Participant.json"
  if ($Participant -match '^[A-Z0-9]+_\d+$' -and (Test-Path $chainFile)) { break }
  Write-Host "  '$Participant' is not a valid code. Use $range." -ForegroundColor Yellow
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
Write-Host "Participant $Participant  ($Study, chain: counterbalance\chains\$Participant.json)"
for ($i = 0; $i -lt $items.Count; $i++) {
  $mark = if ($i + 1 -lt $StartAt) { ' (skipped)' } else { '' }
  Write-Host ("  {0}. {1}{2}" -f ($i + 1), $items[$i].test_name, $mark)
}
Write-Host ""

$log = if ($workspaceDir) { Join-Path $workspaceDir 'logs\launcher-log.csv' } else { $null }
if (-not $DryRun) { Read-Host 'Press Enter to start' | Out-Null }

for ($i = $StartAt - 1; $i -lt $items.Count; $i++) {
  $item = $items[$i]
  $file = Get-TestFile $item.test_name
  $peblArgs = @("`"$file`"", '-s', $Participant, '--language', $item.language)
  if ($item.param_variant -and $item.param_variant -ne 'default') { $peblArgs += @('--pfile', "params/$($item.param_variant).par.json") }
  if ($Fullscreen) { $peblArgs += '--fullscreen' }

  Write-Host ("[{0}/{1}] {2}" -f ($i + 1), $items.Count, $item.test_name)
  if ($DryRun) { Write-Host "  cd `"$(Split-Path $file -Parent)`"; & `"$pebl`" $($peblArgs -join ' ')"; continue }

  $start = Get-Date
  $p = Start-Process -FilePath $pebl -ArgumentList $peblArgs -WorkingDirectory (Split-Path $file -Parent) -Wait -PassThru
  $secs = [int]((Get-Date) - $start).TotalSeconds
  Write-Host "  finished (exit code $($p.ExitCode), $secs s)"

  if ($log) {
    $fs = if ($Fullscreen) { 'true' } else { 'false' }
    $entry = '{0},"{1}","{2}","{3}",{4},{5},{6}' -f $start.ToString('yyyy-MM-dd HH:mm:ss'), $file, $Participant, $item.language, $fs, $p.ExitCode, $secs
    [IO.File]::AppendAllText($log, "$entry`r`n", $utf8NoBom)
  }
}

Write-Host ""
if ($DryRun) { Write-Host 'Dry run: nothing was launched.' } else { Write-Host "All tests done for $Participant." }
'@

try {
  if (-not $env:STUDY_DIR) { throw 'Run setup-study.bat by double-clicking it (or from cmd), not from PowerShell.' }
  $studyDir = $env:STUDY_DIR.TrimEnd('\')
  $testsDir = Join-Path $studyDir 'tests'
  $utilsDir = Join-Path $studyDir 'utils'
  $cbDir    = Join-Path $studyDir 'counterbalance'
  if (-not (Test-Path $testsDir)) { throw "No tests folder in $studyDir. Put setup-study.bat in a study folder." }
  Write-Host "Study: $(Split-Path $studyDir -Leaf)  ($studyDir)"

  # ---------------------------------------------------------------- tests
  $tests = New-Object System.Collections.Generic.List[string]
  $testFiles = @{}
  foreach ($dir in (Get-ChildItem -Path $testsDir -Directory | Sort-Object Name)) {
    $pbls = @(Get-ChildItem -Path $dir.FullName -Filter *.pbl -File)
    $pbl = $pbls | Where-Object { $_.BaseName -eq $dir.Name } | Select-Object -First 1
    if (-not $pbl -and $pbls.Count -eq 1) { $pbl = $pbls[0] }
    if (-not $pbl) { Write-Warning "tests\$($dir.Name): no single .pbl file to run, skipped."; continue }
    $name = if ($pbl.BaseName -ceq $dir.Name) { $dir.Name } else { "$($dir.Name)/$($pbl.BaseName)" }
    $tests.Add($name)
    $testFiles[$name] = $pbl.FullName
  }
  $n = $tests.Count
  if ($n -lt 2) { throw "Found $n test(s) in tests\; need at least 2." }
  if ($n -gt 8) { throw "Found $n tests; $n! orders is too many chains (8 tests = 40320 is the maximum)." }
  $nFact = 1; for ($i = 2; $i -le $n; $i++) { $nFact *= $i }
  Write-Host "Tests ($n): $($tests -join ', ')"

  # ---------------------------------------------------------------- 1. beeps
  Write-Host ""
  Write-Host "1. Beeps"
  if (-not (Test-Path $utilsDir)) { New-Item -ItemType Directory -Path $utilsDir | Out-Null }
  $beepsFile = Join-Path $utilsDir 'beeps.pbl'
  if (-not (Test-Path $beepsFile)) {
    [IO.File]::WriteAllText($beepsFile, $beepsPbl, $utf8NoBom)
    Write-Host "   wrote utils\beeps.pbl"
  }

  $begin  = '## >>> BEGIN beeps.pbl (auto-copied, do not edit)'
  $end    = '## <<< END beeps.pbl'
  $tag    = '## auto-added by setup-study.bat'
  $optOut = '## beeps: no auto calls'
  $lib     = ([IO.File]::ReadAllText($beepsFile)).TrimEnd() -replace "`r?`n", "`r`n"
  $pattern = '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
  $block   = "$begin`r`n$lib`r`n$end"

  # Inserts $call after (or before) the single line matching $anchor
  function Add-Call($text, $anchor, $call, [switch]$Before, $file) {
    $rx = [regex]"(?m)^([ \t]*)$anchor[^\r\n]*(\r?\n)"
    $hits = $rx.Matches($text)
    if ($hits.Count -ne 1) {
      Write-Warning "$file : expected 1 line matching '$anchor', found $($hits.Count). Add $call by hand."
      return $null
    }
    $m = $hits[0]
    $line = "$($m.Groups[1].Value)$call  $tag`r`n"
    if ($Before) { return $text.Insert($m.Index, $line) }
    return $text.Insert($m.Index + $m.Length, $line)
  }

  $updated = 0
  foreach ($dir in (Get-ChildItem -Path $testsDir -Directory)) {
    foreach ($f in (Get-ChildItem -Path $dir.FullName -Filter *.pbl -File)) {
      $file = $f.FullName
      $text = [IO.File]::ReadAllText($file)
      $new = $text
      if (-not ($new.Contains($begin) -and $new.Contains($end))) {
        $new = $new.TrimEnd() + "`r`n`r`n`r`n$begin`r`n$end`r`n"
      }
      $new = [regex]::Replace($new, $pattern, { param($m) $block })
      $outside = [regex]::Replace($new, $pattern, '')
      if (-not $outside.Contains($optOut)) {
        # also accept calls added earlier by sync-beeps.ps1
        if ($outside -notmatch 'BeepsStart\(\)  ## auto-added by') {
          $r = Add-Call $new 'InitializeLSL\(' 'BeepsStart()' -file $file
          if ($r) { $new = $r }
        }
        if ($outside -notmatch 'BeepsEnd\(\)  ## auto-added by') {
          $r = Add-Call $new 'FinalizeLSL\(\)' 'BeepsEnd()' -Before -file $file
          if ($r) { $new = $r }
        }
      }
      $rel = $file.Substring($studyDir.Length + 1)
      if ($new -ne $text) {
        [IO.File]::WriteAllText($file, $new, $utf8NoBom)
        Write-Host "   updated:    $rel"
        $updated++
      } else {
        Write-Host "   up to date: $rel"
      }
    }
  }
  Write-Host "   $updated test file(s) updated."

  # ---------------------------------------------------------------- orders
  $ordersFile = Join-Path $cbDir 'task-orders.csv'
  $rows = $null
  $codes = $null
  if ((Test-Path $ordersFile) -and -not $Force) {
    $lines = [IO.File]::ReadAllLines($ordersFile)
    $first = $lines[1].Split(',')
    $sameTests = (($first | Select-Object -Skip 1 | Sort-Object) -join ',') -eq (($tests | Sort-Object) -join ',')
    $rowCount = @($lines | Select-Object -Skip 1 | Where-Object { $_ }).Count
    if (-not $sameTests -or $rowCount -ne $nFact) {
      throw "counterbalance\task-orders.csv was made for other tests ($(@($first | Select-Object -Skip 1) -join ', ')). Run 'setup-study.bat -Force' to make new orders (participants' orders will change)."
    }
    Write-Host ""
    Write-Host "   Keeping the existing orders in counterbalance\task-orders.csv (use -Force to remake them)."
    $codes = New-Object System.Collections.Generic.List[string]
    $rows  = New-Object System.Collections.Generic.List[string[]]
    for ($i = 1; $i -lt $lines.Count; $i++) {
      if (-not $lines[$i]) { continue }
      $cells = $lines[$i].Split(',')
      $codes.Add($cells[0])
      $rows.Add([string[]]($cells | Select-Object -Skip 1))
    }
  } else {
    # One order per rotation group: test 0 in front, then every order of the
    # other tests (built up one test at a time by inserting it at every position)
    $groups = New-Object System.Collections.Generic.List[int[]]
    $groups.Add([int[]]@(0))
    for ($t = 1; $t -lt $n; $t++) {
      $next = New-Object System.Collections.Generic.List[int[]]
      foreach ($p in $groups) {
        for ($at = 1; $at -le $p.Length; $at++) {
          $q = New-Object int[] ($p.Length + 1)
          [Array]::Copy($p, 0, $q, 0, $at)
          $q[$at] = $t
          [Array]::Copy($p, $at, $q, $at + 1, $p.Length - $at)
          $next.Add($q)
        }
      }
      $groups = $next
    }

    $rng = New-Object System.Random($Seed)
    function Shuffle([System.Collections.Generic.List[int[]]]$list) {
      for ($i = $list.Count - 1; $i -gt 0; $i--) {
        $j = $rng.Next($i + 1)
        $tmp = $list[$i]; $list[$i] = $list[$j]; $list[$j] = $tmp
      }
    }

    Shuffle $groups
    $perms = New-Object System.Collections.Generic.List[int[]]
    foreach ($base in $groups) {
      $rotations = New-Object System.Collections.Generic.List[int[]]
      for ($k = 0; $k -lt $n; $k++) {
        $r = New-Object int[] $n
        for ($pos = 0; $pos -lt $n; $pos++) { $r[$pos] = $base[($pos + $k) % $n] }
        $rotations.Add($r)
      }
      Shuffle $rotations
      $perms.AddRange($rotations)
    }

    # Self-check: every order once, every test equally often in every position,
    # every block of n codes balanced
    $total = $perms.Count
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($p in $perms) { [void]$seen.Add($p -join ',') }
    if ($seen.Count -ne $total) { throw "Self-check failed: $($seen.Count) unique orders out of $total." }
    $counts = New-Object 'int[,]' $n, $n
    foreach ($p in $perms) { for ($pos = 0; $pos -lt $n; $pos++) { $counts[$pos, $p[$pos]]++ } }
    for ($pos = 0; $pos -lt $n; $pos++) {
      for ($t = 0; $t -lt $n; $t++) {
        if ($counts[$pos, $t] -ne $total / $n) { throw "Self-check failed: test $($tests[$t]) appears $($counts[$pos, $t]) times at position $($pos + 1)." }
      }
    }
    for ($b = 0; $b -lt $total; $b += $n) {
      for ($pos = 0; $pos -lt $n; $pos++) {
        $col = @{}
        for ($i = $b; $i -lt $b + $n; $i++) { $col[$perms[$i][$pos]] = $true }
        if ($col.Count -ne $n) { throw "Self-check failed: block starting at row $($b + 1) is not balanced." }
      }
    }

    $width = [Math]::Max(4, "$total".Length)
    $codes = New-Object System.Collections.Generic.List[string]
    $rows  = New-Object System.Collections.Generic.List[string[]]
    for ($i = 0; $i -lt $total; $i++) {
      $codes.Add(('{0}_{1}' -f $Prefix, ($i + 1).ToString().PadLeft($width, '0')))
      $rows.Add([string[]]($perms[$i] | ForEach-Object { $tests[$_] }))
    }
  }

  # ---------------------------------------------------------------- 2. chains
  Write-Host ""
  Write-Host "2. Chains"
  $chainsDir = Join-Path $cbDir 'chains'
  if (Test-Path $chainsDir) { Get-ChildItem -Path $chainsDir -Filter *.json -File | Remove-Item -Force }
  else { New-Item -ItemType Directory -Path $chainsDir -Force | Out-Null }
  for ($i = 0; $i -lt $codes.Count; $i++) {
    $items = ($rows[$i] | ForEach-Object {
      "    {`r`n      `"item_type`": `"test`",`r`n      `"language`": `"$Language`",`r`n      `"param_variant`": `"default`",`r`n      `"random_group`": 0,`r`n      `"test_name`": `"$_`"`r`n    }"
    }) -join ",`r`n"
    $json = "{`r`n  `"chain_name`": `"$($codes[$i])`",`r`n  `"description`": `"Counterbalanced order for $($codes[$i]) (setup-study.bat)`",`r`n  `"items`": [`r`n$items`r`n  ],`r`n  `"lsl_enabled`": false,`r`n  `"lsl_stream_name`": `"PEBL_{test}`",`r`n  `"upload_enabled`": false`r`n}`r`n"
    [IO.File]::WriteAllText((Join-Path $chainsDir "$($codes[$i]).json"), $json, $utf8NoBom)
  }
  Write-Host "   wrote $($codes.Count) chains to counterbalance\chains\ ($($codes[0]) .. $($codes[$codes.Count - 1]))"

  # ---------------------------------------------------------------- 3. orders file
  Write-Host ""
  Write-Host "3. Participant order file"
  $out = New-Object System.Collections.Generic.List[string]
  $out.Add('participant_code,' + ((1..$n | ForEach-Object { "task$_" }) -join ','))
  for ($i = 0; $i -lt $codes.Count; $i++) { $out.Add($codes[$i] + ',' + ($rows[$i] -join ',')) }
  [IO.File]::WriteAllLines($ordersFile, $out, $utf8NoBom)
  Write-Host "   wrote counterbalance\task-orders.csv ($($codes.Count) participants)"

  # ---------------------------------------------------------------- 4. run script
  Write-Host ""
  Write-Host "4. Run script"
  [IO.File]::WriteAllText((Join-Path $utilsDir 'run-participant.ps1'), $runnerPs1, $utf8NoBom)
  $bat = "@echo off`r`nrem Asks for a participant code and runs that participant's counterbalanced chain.`r`nrem Options: run-participant.bat -Participant $($codes[0]) -Fullscreen -StartAt 3 -DryRun`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0utils\run-participant.ps1`" %*`r`npause`r`n"
  [IO.File]::WriteAllText((Join-Path $studyDir 'run-participant.bat'), $bat, $utf8NoBom)
  Write-Host "   wrote run-participant.bat and utils\run-participant.ps1"

  Write-Host ""
  Write-Host "Done. Double-click run-participant.bat to run a participant." -ForegroundColor Green
}
catch {
  Write-Host ""
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
