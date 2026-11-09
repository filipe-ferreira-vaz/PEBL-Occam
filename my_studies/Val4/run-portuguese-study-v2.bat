@echo off
rem Portuguese study v2: asks for the participant ID (1-300; says if data for that ID already exist)
rem and the session (A or B), then runs the European Portuguese tests:
rem   Session A: bigfive-portuguese, affectgrid-portuguese-A,
rem              counterbalanced: vsearch-customize-portuguese (search sizes 40,50,60),
rem                               TNT-custom-stimulus-time-portuguese (4000 ms),
rem                               maze-increasing-difficulty-v1-portuguese, stroop (external),
rem              affectgrid-portuguese-A
rem   Session B: affectgrid-portuguese-B,
rem              counterbalanced: ptrails-pt-portuguese, raven matrices (external), tol-portuguese,
rem                               auditory go/no-go (external),
rem              affectgrid-portuguese-B
rem   After the 2nd counterbalanced test: Survey Ecological Momentary Assessment (external).
rem Orders: counterbalance\portuguese-study-v2-orders.csv (one row per ID, 24 orders per session)
rem Options: run-portuguese-study-v2.bat -Participant 42 -Session A -Fullscreen
rem Before each test: Enter = run it, s = skip, b = back to the previous test, q = quit
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-portuguese-study-v2.ps1" %*
pause
