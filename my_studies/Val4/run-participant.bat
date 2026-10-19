@echo off
rem Asks for a participant code and runs that participant's counterbalanced chain.
rem Options: run-participant.bat -Participant PART_0001 -Fullscreen -StartAt 3 -DryRun
rem Between tests: Enter = next test, b = go back to the previous test, q = quit
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-participant.ps1" %*
pause
