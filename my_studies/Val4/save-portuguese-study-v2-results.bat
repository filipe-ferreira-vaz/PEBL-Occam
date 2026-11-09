@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Portuguese study v2: copies the results of one participant's session to
rem   <destination>\study_results\<ID>_<session>\<test>\<result files>
rem It asks for the participant ID, the session (A or B) and where to save
rem (Enter = this study folder; type e.g. E:\ to save on a USB drive).
rem Only the files in tests\<test>\data\<ID>\ of that session's tests are copied
rem (the pooled files with every participant are not).
rem   Session A: bigfive-portuguese, affectgrid-portuguese-A, vsearch-customize-portuguese,
rem              TNT-custom-stimulus-time-portuguese, maze-increasing-difficulty-v1-portuguese
rem   Session B: affectgrid-portuguese-B, ptrails-pt-portuguese, tol-portuguese
rem Stroop, Raven, go/no-go and the EMA survey are run outside PEBL: save their results by hand.

set "STUDY=%~dp0"
set "TESTS=%STUDY%tests"

:ask_id
set "ID="
set /p "ID=Participant ID (1-300): "
if not defined ID goto ask_id
set "ID=%ID: =%"
if not defined ID goto ask_id
echo %ID%| findstr /r "^[1-9]$ ^[1-9][0-9]$ ^[1-9][0-9][0-9]$" >nul || (echo   Type a whole number from 1 to 300.& goto ask_id)
if %ID% GTR 300 (echo   Type a whole number from 1 to 300.& goto ask_id)

:ask_session
set "SESSION="
set /p "SESSION=Session (A or B): "
if not defined SESSION goto ask_session
set "SESSION=%SESSION: =%"
if /i "%SESSION%"=="A" (set "SESSION=A" & goto ask_dest)
if /i "%SESSION%"=="B" (set "SESSION=B" & goto ask_dest)
echo   Type A or B.
goto ask_session

:ask_dest
set "DEST="
set /p "DEST=Save to which folder or drive (Enter = %STUDY:~0,-1%): "
if not defined DEST set "DEST=%STUDY%"
if "%DEST:~-1%"=="\" set "DEST=%DEST:~0,-1%"
if not exist "%DEST%\" (echo   Folder not found: %DEST%& goto ask_dest)

if "%SESSION%"=="A" (
  set "LIST=bigfive-portuguese affectgrid-portuguese-A vsearch-customize-portuguese TNT-custom-stimulus-time-portuguese maze-increasing-difficulty-v1-portuguese"
) else (
  set "LIST=affectgrid-portuguese-B ptrails-pt-portuguese tol-portuguese"
)

set "OUT=%DEST%\study_results\%ID%_%SESSION%"
if exist "%OUT%\" (
  echo   %OUT% already exists.
  set "ANSWER="
  set /p "ANSWER=  Enter = replace it, n = cancel: "
  if /i "!ANSWER!"=="n" (echo Cancelled. & goto end)
  rmdir /s /q "%OUT%"
)
mkdir "%OUT%" || (echo Could not create %OUT% & goto end)

echo.
echo Saving participant %ID%, session %SESSION% to %OUT%
set /a COPIED=0
set /a MISSING=0
for %%T in (%LIST%) do (
  set "SRC=%TESTS%\%%T\data\%ID%"
  if exist "!SRC!\*" (
    mkdir "%OUT%\%%T"
    xcopy "!SRC!\*" "%OUT%\%%T\" /E /I /Y /Q >nul
    set "N=0"
    for /f %%C in ('dir /b /s /a-d "%OUT%\%%T" ^| "%SystemRoot%\System32\find.exe" /c /v ""') do set "N=%%C"
    echo   %%T: !N! file^(s^)
    set /a COPIED+=1
  ) else (
    echo   %%T: NO DATA for participant %ID%
    set /a MISSING+=1
  )
)

echo.
if %COPIED% EQU 0 (
  rmdir "%OUT%"
  echo No data found for participant %ID% - nothing saved. Check the ID.
  goto end
)
echo %COPIED% test^(s^) saved to %OUT%
if %MISSING% GTR 0 echo %MISSING% test^(s^) had no data for participant %ID% - check above.
if "%SESSION%"=="A" echo Remember to save the Stroop and EMA survey results ^(done outside PEBL^).
if "%SESSION%"=="B" echo Remember to save the Raven, go/no-go and EMA survey results ^(done outside PEBL^).

:end
echo.
pause
