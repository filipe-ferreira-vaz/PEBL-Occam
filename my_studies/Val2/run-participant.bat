@echo off
rem Runs the Val2 tests in the counterbalanced order of a participant code (PART_0001 .. PART_5040).
rem Extra options are passed on, e.g.: run-participant.bat -Participant PART_0042 -Fullscreen
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\lib\run-counterbalanced.ps1" -Study Val2 %*
pause
