## This PC (fixed facts; check anything else yourself)
<!-- Copy to environment.md next to the launchers and edit it for your machine. The planner, reviewer and executor all
     read it. It prevents whole classes of mistakes: calling a missing python3, binding the port your model server is
     on, killing the model server by name. Add every fact a model got wrong twice. -->
- Windows 11. The bash tool runs Git Bash (`/c/Users/...` and `C:/Users/...` both work; no WSL). Use forward slashes in paths.
- Python: `python` (3.12). There is no `python3` command.
- Node: `node`. git, curl and `timeout` are available in bash.
- Ports already in use, never bind them: 8080 (llama-swap, the model you are running on; killing it kills you). Pick a port in 7000-7999 and test it is free with `netstat -ano | grep :PORT`.
- GUI programs (game engines, browsers) must always run with `timeout`, and never as part of a test suite.
- Never kill processes by name (node, python, llama*); you may only stop a process you started yourself.
