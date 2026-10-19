@echo off
rem Asks for a participant code, then lets you pick single tests to run (number = run it, q = quit).
rem Options: run-test.bat -Participant PART_0001 -Fullscreen -Language en
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-test.ps1" -Language en %*
pause
