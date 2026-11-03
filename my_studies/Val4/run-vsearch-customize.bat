@echo off
rem Asks for a participant code, search sizes and numbers of targets, then runs vsearch-customize with them.
rem Options: run-vsearch-customize.bat -Participant PART_0001 -Fullscreen -Language en
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-vsearch-customize.ps1" -Language en %*
pause
