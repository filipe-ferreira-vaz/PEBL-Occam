@echo off
rem PROOF OF CONCEPT: runs all tests in alphabetical order, alternating with affectgrid.
rem Options: run-affect-chain.bat -Participant PART_0001 -Fullscreen -StartAt 3 -DryRun
rem Between tests: Enter = next test, b = go back to the previous test, q = quit
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-affect-chain.ps1" %*
pause
