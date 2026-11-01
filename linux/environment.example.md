## This PC (fixed facts; check anything else yourself)
<!-- Copy to environment.md next to the launchers and edit it for your machine. The planner, reviewer and executor all
     read it. Add every fact a model got wrong twice. -->
- Linux (Lubuntu 26.04). The bash tool runs bash; use normal Linux paths. Home is /home/freddy.
- Python: `python3` (3.14); `python` is a link to it. Use `python3 -m venv .venv` for packages (pip into the system Python is blocked).
- Node: `node`, `npm`. git, curl, tar and `timeout` are available. There is no `lua`/`luajit` or `love` unless a plan installs them.
- Ports already in use, never bind them: 8080 (llama-swap, the model you are running on; killing it kills you) and 10001-10010 (its model servers). Pick a port in 7000-7999 and test it is free with `ss -ltn | grep :PORT`.
- GUI programs (game engines, browsers) must always run with `timeout`, and never as part of a test suite.
- Never kill processes by name (`pkill`/`killall` node, python, llama*); you may only stop a process you started yourself, by its PID.
- No sudo: the password is not available. Don't run `apt`; install what you need per-project (venv, npm in the project).
