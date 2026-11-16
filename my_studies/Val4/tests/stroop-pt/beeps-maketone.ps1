param([double]$f,[int]$d,[double]$a,[string]$o)
$sr=44100; $n=[int]($sr*$d/1000); $ms=New-Object IO.MemoryStream; $w=New-Object IO.BinaryWriter($ms)
$w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36+$n*2)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
$w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$sr); $w.Write([int]($sr*2)); $w.Write([int16]2); $w.Write([int16]16)
$w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]($n*2))
for($i=0;$i -lt $n;$i++){ $w.Write([int16][Math]::Round(32767*$a*[Math]::Sin(2*[Math]::PI*$f*$i/$sr))) }
$w.Flush(); [IO.File]::WriteAllBytes((Join-Path (Get-Location) $o),$ms.ToArray())
