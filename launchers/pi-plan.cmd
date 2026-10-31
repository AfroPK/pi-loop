@echo off
REM PLANNER: Swift 1.5 27B (llama-swap id swift27-xs-64k, 48K ctx) at thinking medium. Writes PLAN.md, PLAN.notes.md,
REM PLAN.files/ (code written once) and PLAN.next.md (later slices). It may run bash for checks and a rehearsal in
REM PLAN.rehearsal/, but planner.md forbids changing project files.
REM Usage: pi-plan "task" [pi args]   |   pi-plan TASK.md   |   pi-plan   (no task: plan the next slice of PLAN.next.md)
REM Add -p to plan non-interactively. For big or vague tasks: pi-plan --thinking xhigh "task"
setlocal
set "MODEL_ID=swift27-xs-64k"
set "PI_MODEL=qwen27/swift27-xs-64k"
set "FIRST=%~1"
set "NEXTMODE="
if "%FIRST%"=="" set "NEXTMODE=1"
if "%FIRST:~0,1%"=="-" set "NEXTMODE=1"
if not defined NEXTMODE goto server
if not exist "PLAN.next.md" (
    echo No task given and no PLAN.next.md here. Usage: pi-plan "task"   or   pi-plan TASK.md
    exit /b 1
)
if not exist "PLAN.md" goto server
REM Never overwrite a plan that still has open boxes
findstr /r /c:"^- \[ \]" "PLAN.md" >nul
if not errorlevel 1 (
    echo PLAN.md still has unticked items - run pi-exec to finish it first, or move it away.
    exit /b 1
)
set /a N=1
:nextname
if exist "PLAN.done-%N%.md" (set /a N+=1 & goto nextname)
move /Y "PLAN.md" "PLAN.done-%N%.md" >nul
echo Archived the finished PLAN.md as PLAN.done-%N%.md
:server
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ensure-server.ps1" -Alias %MODEL_ID%
if errorlevel 1 exit /b 1
REM Full node path: a stray quote in PATH can hide node from cmd's PATH search
set PI="C:\Program Files\nodejs\node.exe" "%APPDATA%\npm\node_modules\@earendil-works\pi-coding-agent\dist\cli.js" --model %PI_MODEL% --thinking medium --no-skills --tools "read,grep,find,ls,write,edit,bash" --append-system-prompt "%~dp0local-session.md" --append-system-prompt "%~dp0environment.md" --append-system-prompt "%~dp0planner.md" --name "plan"
REM goto instead of an if-block: a task text with ( ) in %* would break a block
if not defined NEXTMODE goto plain
%PI% %* "Plan the next slice: the FIRST '## Slice' section of PLAN.next.md is your whole task. Read it, then follow the planner rules. When PLAN.md is written, remove that section from PLAN.next.md with the edit tool (keep the other slices); if no slices are left, delete PLAN.next.md."
goto :eof
:plain
%PI% %*
