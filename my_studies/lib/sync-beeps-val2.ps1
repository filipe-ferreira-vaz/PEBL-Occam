# Adds the beeps library (my_studies/lib/beeps.pbl) and the standard start/end
# beeps to every test of a study, and keeps them up to date.
#
# Usage (from my_studies or anywhere):
#   powershell -ExecutionPolicy Bypass -File my_studies/lib/sync-beeps.ps1
#   powershell -ExecutionPolicy Bypass -File my_studies/lib/sync-beeps.ps1 -Study Occam
#   powershell -ExecutionPolicy Bypass -File my_studies/lib/sync-beeps.ps1 -Study OpenCode,Occam
#
# For each test (my_studies/<Study>/tests/<test>/*.pbl) it:
#   1. appends these marker lines at the end of the file, if missing:
#        ## >>> BEGIN beeps.pbl (auto-copied, do not edit)
#        ## <<< END beeps.pbl
#   2. replaces everything between the markers with the current beeps.pbl
#   3. adds, once:
#        BeepsStart()  after the InitializeLSL(...) line  (window just opened)
#        BeepsEnd()    before the FinalizeLSL() line      (test finished)
#      Every PEBL 2.4 test has both lines; if one is missing it prints a warning.
#
# Files elsewhere under my_studies that already contain the markers are also
# refreshed (step 2 and 3), whatever study they are in.
#
# To keep a test silent, put this line anywhere in it (outside the library block):
#   ## beeps: no auto calls
# The library is still copied in (its functions stay usable), but no calls are added.
#
# Running the script again changes nothing unless beeps.pbl or the tests changed.

param([string[]]$Study = @('Val2'))

$ErrorActionPreference = 'Stop'
$libDir     = $PSScriptRoot
$studiesDir = Split-Path $libDir -Parent
$begin      = '## >>> BEGIN beeps.pbl (auto-copied, do not edit)'
$end        = '## <<< END beeps.pbl'
$tag        = '## auto-added by sync-beeps.ps1'
$optOut     = '## beeps: no auto calls'

$lib = ([IO.File]::ReadAllText((Join-Path $libDir 'beeps.pbl'))).TrimEnd() -replace "`r?`n", "`r`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$pattern = '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
$block   = "$begin`r`n$lib`r`n$end"

# Inserts $call after (or before) the single line matching $anchor, keeping its
# indentation. Returns the new text, or $null (with a warning) if there isn't
# exactly one such line.
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

# Test files of the selected studies: the .pbl files directly inside each test folder
$targets = @{}
foreach ($s in $Study) {
  $testsDir = Join-Path (Join-Path $studiesDir $s) 'tests'
  if (-not (Test-Path $testsDir)) { Write-Warning "No tests folder for study '$s' ($testsDir)"; continue }
  Get-ChildItem -Path $testsDir -Directory | ForEach-Object {
    Get-ChildItem -Path $_.FullName -Filter *.pbl -File | ForEach-Object { $targets[$_.FullName] = $true }
  }
}
# ...plus any file under my_studies that already has the markers
Get-ChildItem -Path $studiesDir -Recurse -Filter *.pbl -File |
  Where-Object { -not $_.FullName.StartsWith($libDir) -and $_.FullName -notmatch '\\data\\' } |
  ForEach-Object {
    if ([IO.File]::ReadAllText($_.FullName).Contains($begin)) { $targets[$_.FullName] = $true }
  }

$updated = 0
foreach ($file in ($targets.Keys | Sort-Object)) {
  $text = [IO.File]::ReadAllText($file)
  $new = $text

  # 1. markers
  if (-not ($new.Contains($begin) -and $new.Contains($end))) {
    $new = $new.TrimEnd() + "`r`n`r`n`r`n$begin`r`n$end`r`n"
  }

  # 2. library
  $new = [regex]::Replace($new, $pattern, { param($m) $block })

  # 3. start/end calls (the opt-out line is looked for outside the library
  #    block, because the library header mentions it)
  $outside = [regex]::Replace($new, $pattern, '')
  if (-not $outside.Contains($optOut)) {
    if (-not $new.Contains("BeepsStart()  $tag")) {
      $r = Add-Call $new 'InitializeLSL\(' 'BeepsStart()' -file $file
      if ($r) { $new = $r }
    }
    if (-not $new.Contains("BeepsEnd()  $tag")) {
      $r = Add-Call $new 'FinalizeLSL\(\)' 'BeepsEnd()' -Before -file $file
      if ($r) { $new = $r }
    }
  }

  if ($new -ne $text) {
    [IO.File]::WriteAllText($file, $new, $utf8NoBom)
    Write-Host "updated:    $file"
    $updated++
  } else {
    Write-Host "up to date: $file"
  }
}
Write-Host "$updated file(s) updated."
