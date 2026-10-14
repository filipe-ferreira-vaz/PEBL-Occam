# Writes the hardcoded, counterbalanced task order of every participant code
# of a study: one row per possible order of its tests (7 tests -> 7! = 5040
# rows, PART_0001 .. PART_5040).
#
# Usage (from anywhere):
#   powershell -ExecutionPolicy Bypass -File my_studies/lib/make-counterbalance-orders.ps1
#   powershell -ExecutionPolicy Bypass -File my_studies/lib/make-counterbalance-orders.ps1 -Study Val2 -Force
#
# Tests are the included tests of my_studies/<Study>/study-info.json, in order.
# Output: my_studies/<Study>/counterbalance/task-orders.csv
#   participant_code,task1,task2,...,taskN
#
# Counterbalancing: rotating an order (abcdefg -> bcdefga -> ...) splits all
# N! orders into (N-1)! groups of N, and each group is a Latin square (every
# test once in every position). The groups, and the rows inside each group,
# are shuffled with a fixed seed and then numbered. So every block of N
# consecutive codes (PART_0001-0007, PART_0008-0014, ...) is position-balanced,
# and all N! codes together use every order exactly once.
#
# The seed makes the file reproducible. An existing file is never overwritten
# unless -Force is given, so orders already handed out stay the same.

param(
  [string]$Study = 'Val2',
  [string]$Prefix = 'PART',
  [int]$Seed = 20261014,
  [string]$OutFile,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$studiesDir = Split-Path $PSScriptRoot -Parent
$studyDir   = Join-Path $studiesDir $Study
if (-not $OutFile) { $OutFile = Join-Path $studyDir 'counterbalance\task-orders.csv' }

if ((Test-Path $OutFile) -and -not $Force) {
  throw "$OutFile already exists. Use -Force to overwrite it (participants' orders would change if the tests or seed changed)."
}

$info  = Get-Content (Join-Path $studyDir 'study-info.json') -Raw | ConvertFrom-Json
$tests = @($info.tests | Where-Object { $_.included } | ForEach-Object { $_.test_name })
$n = $tests.Count
if ($n -lt 2) { throw "Study $Study has $n included tests; need at least 2." }

# One order per rotation group: test 0 in front, then every order of tests
# 1..n-1 (built up one test at a time by inserting it at every position)
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
$rows = New-Object System.Collections.Generic.List[int[]]
foreach ($base in $groups) {
  $rotations = New-Object System.Collections.Generic.List[int[]]
  for ($k = 0; $k -lt $n; $k++) {
    $r = New-Object int[] $n
    for ($pos = 0; $pos -lt $n; $pos++) { $r[$pos] = $base[($pos + $k) % $n] }
    $rotations.Add($r)
  }
  Shuffle $rotations
  $rows.AddRange($rotations)
}

# Self-check: every order once, every test equally often in every position
$total = $rows.Count
$unique = @($rows | ForEach-Object { $_ -join ',' } | Sort-Object -Unique).Count
if ($unique -ne $total) { throw "Self-check failed: $unique unique orders out of $total." }
$perCell = $total / $n
for ($pos = 0; $pos -lt $n; $pos++) {
  $counts = $rows | ForEach-Object { $_[$pos] } | Group-Object
  foreach ($c in $counts) {
    if ($c.Count -ne $perCell) { throw "Self-check failed: test $($c.Name) appears $($c.Count) times at position $($pos + 1)." }
  }
}
for ($b = 0; $b -lt $total; $b += $n) {
  for ($pos = 0; $pos -lt $n; $pos++) {
    $col = @($b..($b + $n - 1) | ForEach-Object { $rows[$_][$pos] } | Sort-Object -Unique)
    if ($col.Count -ne $n) { throw "Self-check failed: block starting at row $($b + 1) is not balanced." }
  }
}

$width = [Math]::Max(4, "$total".Length)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('participant_code,' + ((1..$n | ForEach-Object { "task$_" }) -join ','))
for ($i = 0; $i -lt $total; $i++) {
  $code = '{0}_{1}' -f $Prefix, ($i + 1).ToString().PadLeft($width, '0')
  $lines.Add($code + ',' + (($rows[$i] | ForEach-Object { $tests[$_] }) -join ','))
}

$dir = Split-Path $OutFile -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[IO.File]::WriteAllLines($OutFile, $lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Tests ($n): $($tests -join ', ')"
Write-Host "Wrote $total orders to $OutFile"
Write-Host "Self-check OK: all orders unique; each test $perCell times per position; every block of $n codes balanced."
