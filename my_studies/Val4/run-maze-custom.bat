@echo off
rem Asks for a participant code and which of the 25 stored mazes to present, in order, then runs maze-custom with them.
rem Options: run-maze-custom.bat -Participant PART_0001 -Fullscreen -Language en
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-maze-custom.ps1" -Language en %*
pause
