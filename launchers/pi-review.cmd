@echo off
REM REVIEWER: a FRESH Swift session (clean context, thinking medium) checks PLAN.md against the task and appends a
REM "### REVIEW CORRECTIONS" block + one extra step above ## Verify. It never deletes or rewrites existing steps.
REM Usage: pi-review [TASK-file] [pi args]   (add -p to run non-interactively)
setlocal
set "MODEL_ID=swift27-xs-64k"
set "PI_MODEL=qwen27/swift27-xs-64k"
if not exist "PLAN.md" (
    echo No PLAN.md in %CD% - run pi-plan first.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ensure-server.ps1" -Alias %MODEL_ID%
if errorlevel 1 exit /b 1
set "TASKARG=Review PLAN.md now."
if "%~1"=="" goto run
if not exist "%~1" goto run
set "TASKARG=Review PLAN.md now. The task it was planned from is in %~1 - read it first."
shift
:run
"C:\Program Files\nodejs\node.exe" "%APPDATA%\npm\node_modules\@earendil-works\pi-coding-agent\dist\cli.js" --model %PI_MODEL% --thinking medium --no-skills --tools "read,grep,find,ls,edit,bash" --append-system-prompt "%~dp0local-session.md" --append-system-prompt "%~dp0environment.md" --append-system-prompt "%~dp0reviewer.md" --name "review" %1 %2 %3 %4 "%TASKARG%"
