@echo off
REM One-shot planner/reviewer/executor: pi-plan writes PLAN.md non-interactively (medium), pi-review (fresh session, medium)
REM appends review corrections non-interactively, then pi-exec opens interactively (low) to carry it out.
REM Usage: pi-pe "task description"   or   pi-pe TASK.md   (a file is passed as @file to the planner and to the reviewer)
setlocal
if "%~1"=="" (
    echo Usage: pi-pe "task description"  or  pi-pe TASK.md
    exit /b 1
)
REM Keep the previous plan as PLAN.old.md so a stale PLAN.md is never executed
if exist "PLAN.md" move /Y "PLAN.md" "PLAN.old.md" >nul
if exist "PLAN.notes.md" del "PLAN.notes.md"
if exist "PLAN.files" rmdir /s /q "PLAN.files"
if exist "PLAN.rehearsal" rmdir /s /q "PLAN.rehearsal"
REM A new task must not inherit slices left over from an older task
if exist "PLAN.next.md" move /Y "PLAN.next.md" "PLAN.next.old.md" >nul
if not exist "%~1" goto textask
copy /Y "%~1" "PLAN.task.md" >nul
goto planit
:textask
REM Task text can hold ( ) & | - write it via an env var so cmd never parses it
set "PE_TASK=%~1"
powershell -NoProfile -Command "Set-Content -Encoding utf8 -Path 'PLAN.task.md' -Value $env:PE_TASK"
:planit
call "%~dp0pi-plan.cmd" -p "Plan the task described in PLAN.task.md (read it first)."
if errorlevel 1 exit /b 1
if not exist "PLAN.md" (
    echo Planner did not write PLAN.md - run pi-plan interactively to see why.
    exit /b 1
)
call "%~dp0pi-review.cmd" PLAN.task.md -p
if errorlevel 1 echo Review failed - executing the unreviewed plan.
call "%~dp0pi-exec.cmd"
