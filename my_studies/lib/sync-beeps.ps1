# Copies my_studies/lib/beeps.pbl into every .pbl test under my_studies that
# contains the marker lines below. Everything between the markers is replaced.
#
#   ## >>> BEGIN beeps.pbl (auto-copied, do not edit)
#   ## <<< END beeps.pbl
#
# To add the library to a new test: paste those two lines at the end of the
# test's .pbl file, then run:
#   powershell -ExecutionPolicy Bypass -File my_studies/lib/sync-beeps.ps1

$ErrorActionPreference = 'Stop'
$libDir     = $PSScriptRoot
$studiesDir = Split-Path $libDir -Parent
$begin      = '## >>> BEGIN beeps.pbl (auto-copied, do not edit)'
$end        = '## <<< END beeps.pbl'

$lib = ([IO.File]::ReadAllText((Join-Path $libDir 'beeps.pbl'))).TrimEnd() -replace "`r?`n", "`r`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$pattern = '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
$block   = "$begin`r`n$lib`r`n$end"

$updated = 0
Get-ChildItem -Path $studiesDir -Recurse -Filter *.pbl |
  Where-Object { -not $_.FullName.StartsWith($libDir) } |
  ForEach-Object {
    $text = [IO.File]::ReadAllText($_.FullName)
    if ($text.Contains($begin) -and $text.Contains($end)) {
      $new = [regex]::Replace($text, $pattern, { param($m) $block })
      if ($new -ne $text) {
        [IO.File]::WriteAllText($_.FullName, $new, $utf8NoBom)
        Write-Host "updated:    $($_.FullName)"
        $updated++
      } else {
        Write-Host "up to date: $($_.FullName)"
      }
    }
  }
Write-Host "$updated file(s) updated."
