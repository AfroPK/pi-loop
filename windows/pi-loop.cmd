@echo off
REM pi-loop for Windows: runs the repo's bash scripts (..\linux\) under Git Bash, with windows\bin\ (python3 and
REM systemctl shims) first on PATH. Copy nothing: put this folder on PATH, or call it by full path.
REM Usage (in a project folder): pi-loop "task" | pi-loop TASK.md | pi-loop (resume) | --max-slices N --max-fix-rounds N
REM   pi-loop --tui ...             full-screen view (needs: pip install windows-curses)
REM   pi-loop --run <script> args   another repo script, e.g. pi-loop --run pi-code-review -p
REM Task text with & | < > ( ) breaks in cmd: put it in a TASK.md. Git Bash: PI_BASH, else Git for Windows' default.
setlocal
set "PATH=%~dp0bin;%PATH%"
set "PI_LOOP_WIN=%~dp0"
if not defined PI_BASH set "PI_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%PI_BASH%" (echo [pi-loop] Git Bash not found at %PI_BASH% - install Git for Windows or set PI_BASH & exit /b 1)
"%PI_BASH%" -c "w=$(cygpath -u \"$PI_LOOP_WIN\"); for a; do [ \"$a\" = --tui ] && exec python3 \"$w/pi-loop-tui-win.py\" \"$@\"; done; c=pi-loop; if [ \"$1\" = --run ]; then c=$2; shift 2; fi; exec \"$w/../linux/$c\" \"$@\"" pi-loop %*
