@echo off
rem Asks for a participant code and the maze dimension N (and optionally a seed), then runs maze-custom-dimension with one new N x N maze.
rem Options: run-maze-custom-dimension.bat -Participant PART_0001 -Dimension 20 -Seed 481516 -Fullscreen -Language en
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-maze-custom-dimension.ps1" -Language en %*
pause
