"""Runs linux/pi-loop-tui on Windows (needs: pip install windows-curses). Patches the POSIX-only parts it uses:
it starts the bash pi-loop script (and --cmd's /bin/sh) through Git Bash, decodes the feed as UTF-8, and stops
the run with Ctrl-Break to its process group instead of os.killpg. Git Bash: PI_BASH, else Git for Windows' default location."""
import os, runpy, signal, subprocess, sys

HERE = os.path.dirname(os.path.realpath(__file__))
TUI = os.path.join(HERE, "..", "linux", "pi-loop-tui")
BASH = os.environ.get("PI_BASH") or os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "Git", "bin", "bash.exe")

_Popen = subprocess.Popen
class Popen(_Popen):
    def __init__(self, cmd, *a, **k):
        if isinstance(cmd, list) and cmd:
            if cmd[0] == "/bin/sh": cmd = [BASH] + cmd[1:]
            elif os.path.basename(cmd[0]) == "pi-loop": cmd = [BASH, cmd[0].replace("\\", "/")] + cmd[1:]
        if k.pop("start_new_session", None):   # own console process group, so killpg can Ctrl-Break all of it
            k["creationflags"] = k.get("creationflags", 0) | subprocess.CREATE_NEW_PROCESS_GROUP
        if k.get("text") or k.get("universal_newlines"):
            k.setdefault("encoding", "utf-8"); k.setdefault("errors", "replace")
        super().__init__(cmd, *a, **k)
subprocess.Popen = Popen

def killpg(pid, sig):
    # Git Bash's children don't show up as Windows child processes, so taskkill /T misses pi and its tools.
    # Ctrl-Break reaches every process in the group (bash pi-loop -> pi/node -> tools), like Ctrl-C in a terminal.
    if sig == signal.SIGINT:
        os.kill(pid, signal.CTRL_BREAK_EVENT)
    else:
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], capture_output=True)
os.killpg = killpg
if not hasattr(signal, "SIGKILL"): signal.SIGKILL = signal.SIGTERM

# windows-curses delivers Ctrl-C as key 3 instead of SIGINT; raise it like Linux does, so the TUI's exit path stops the run.
import curses
class _Screen:
    def __init__(self, scr): self._scr = scr
    def __getattr__(self, name): return getattr(self._scr, name)
    def getch(self, *a):
        k = self._scr.getch(*a)
        if k == 3: raise KeyboardInterrupt
        return k
_wrapper = curses.wrapper
curses.wrapper = lambda fn, *a, **k: _wrapper(lambda scr, *a2, **k2: fn(_Screen(scr), *a2, **k2), *a, **k)

sys.argv = [TUI] + sys.argv[1:]
runpy.run_path(TUI, run_name="__main__")
