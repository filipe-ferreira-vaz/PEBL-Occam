@echo off
rem Trial study Nov 5: asks for a participant code, then runs
rem   Session A: vsearch-customize (search sizes 40,50,60), TNT-custom-stimulus-time (4000 ms),
rem              maze-custom-dimension (5 random 15x15 mazes, then 3 random 20x20; every maze saved in its data folder)
rem   Session B: ptrails-pt, TOL
rem Options: trial-study-nov-5.bat -Participant PART_0001 -Fullscreen -Language en
rem Before each test: Enter = run it, s = skip, q = quit
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\trial-study-nov-5.ps1" -Language en %*
pause
