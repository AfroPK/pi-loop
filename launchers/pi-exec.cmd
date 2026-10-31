@echo off
REM EXECUTOR: Ornith 1.5 9B Q8 (llama-swap id ornith9b-q8, 80K ctx, ~62 tok/s) at thinking low, full tools.
REM Follows PLAN.md step by step, ticks boxes only with proof, writes to ## Blockers when stuck.
REM Usage: pi-exec [pi args]   (in the folder where pi-plan wrote PLAN.md; add -p to run non-interactively)
REM Coming from the planner costs one llama-swap model swap (~35-40 s).
setlocal
set "MODEL_ID=ornith9b-q8"
set "PI_MODEL=ornith/ornith9b-q8"
if not exist "PLAN.md" (
    echo No PLAN.md in %CD% - run pi-plan "task" here first.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ensure-server.ps1" -Alias %MODEL_ID%
if errorlevel 1 exit /b 1
"C:\Program Files\nodejs\node.exe" "%APPDATA%\npm\node_modules\@earendil-works\pi-coding-agent\dist\cli.js" --model %PI_MODEL% --thinking low --no-skills --append-system-prompt "%~dp0local-session.md" --append-system-prompt "%~dp0environment.md" --append-system-prompt "%~dp0executor.md" --name "exec" @PLAN.md "Execute PLAN.md now, step by step." %*
