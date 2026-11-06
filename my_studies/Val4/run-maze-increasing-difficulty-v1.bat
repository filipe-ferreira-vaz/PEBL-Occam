@echo off
rem Asks for a participant code, then runs maze-increasing-difficulty-v1: the practice maze, then 8 mazes from the shortest to the longest shortest path.
rem Options: run-maze-increasing-difficulty-v1.bat -Participant PART_0001 -Fullscreen -Language en
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-maze-increasing-difficulty-v1.ps1" -Language en %*
pause
