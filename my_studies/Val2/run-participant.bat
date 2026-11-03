@echo off
rem Runs this study's tests in the counterbalanced order of a participant code (e.g. PART_0001 .. PART_5040).
rem Works in any study folder that has a utils folder next to it.
rem Extra options are passed on, e.g.: run-participant.bat -Participant PART_0042 -Fullscreen
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-counterbalanced.ps1" %*
pause
