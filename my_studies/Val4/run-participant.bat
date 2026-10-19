@echo off
rem Asks for a participant code and runs that participant's counterbalanced chain.
rem Options: run-participant.bat -Participant PART_0001 -Fullscreen -StartAt 3 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-participant.ps1" %*
pause
