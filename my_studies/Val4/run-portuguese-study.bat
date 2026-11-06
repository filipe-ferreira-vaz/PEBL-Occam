@echo off
rem Portuguese study: asks for the participant ID (1-300) and the session (A or B), then runs
rem the European Portuguese tests in a counterbalanced order (set by the participant ID):
rem   Session A: vsearch-customize-portuguese (search sizes 40,50,60), TNT-custom-stimulus-time-portuguese (4000 ms),
rem              maze-increasing-difficulty-v1-portuguese
rem   Session B: ptrails-pt-portuguese, tol-portuguese
rem Options: run-portuguese-study.bat -Participant 42 -Session A -Fullscreen
rem Before each test: Enter = run it, s = skip, q = quit
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-portuguese-study.ps1" %*
pause
