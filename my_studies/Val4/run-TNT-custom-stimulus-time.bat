@echo off
rem Asks for a participant code and the stimulus duration, then runs TNT-custom-stimulus-time with it.
rem Options: run-TNT-custom-stimulus-time.bat -Participant PART_0001 -Fullscreen -Language en
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-TNT-custom-stimulus-time.ps1" -Language en %*
pause
