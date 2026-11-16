@echo off
rem Asks for the participant ID (1-300) and the test version (A or B), then runs stroop-pt
rem (Portuguese color Stroop: fixation 0 ms, ISI 0 ms, 120 s per block; color-key mapping from
rem counterbalance\stroop-pt-keys.csv).
rem   A = paper-sheet order, reading block + naming block   B = 112 mixed trials, naming block
rem Options: run-stroop-pt.bat -Participant 42 -Version B -Fullscreen
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-stroop-pt.ps1" %*
pause
