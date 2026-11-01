#!/usr/bin/env python3
"""pi-feed.py LABEL [LOG]: turn `pi --mode json` events on stdin into one short line per action.
Raw events are saved to LOG (if given) so the full session can be inspected afterwards."""
import json, os, sys, time

label = sys.argv[1] if len(sys.argv) > 1 else "pi"
log = open(sys.argv[2], "w") if len(sys.argv) > 2 else None
tty = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
C = {"dim": "\033[2m", "red": "\033[31m", "grn": "\033[32m", "ylw": "\033[33m", "cyn": "\033[36m", "off": "\033[0m"}
def c(k, s): return f"{C[k]}{s}{C['off']}" if tty else s

t0 = time.time()
def stamp(): s = int(time.time() - t0); return f"{s // 60:2d}:{s % 60:02d}"
def say(msg): print(f"{c('dim', stamp())} {c('cyn', f'[{label}]')} {msg}", flush=True)

def one_line(s, n=90):
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1] + "…"

def describe(tool, args):
    a = args or {}
    if tool == "bash": return one_line(a.get("command", ""), 80)
    if tool in ("read", "write", "edit"): return a.get("path") or a.get("file_path") or ""
    if tool in ("grep", "find", "ls"): return one_line(" ".join(str(v) for v in a.values()), 80)
    return one_line(json.dumps(a), 80)

thinking = out_tokens = tools = 0
last_text = ""
starts = {}
for line in sys.stdin:
    if log: log.write(line); log.flush()
    try:
        try: e = json.loads(line)
        except ValueError: continue
        t = e.get("type")
        if t == "message_update":
            ev = e.get("assistantMessageEvent") or {}
            if ev.get("type") == "thinking_delta": thinking += len(ev.get("delta", ""))
        elif t == "tool_execution_start":
            tools += 1; starts[e.get("toolCallId")] = time.time()
            say(f"▸ {e.get('toolName')}  {describe(e.get('toolName'), e.get('args'))}")
        elif t == "tool_execution_end":
            dur = time.time() - starts.pop(e.get("toolCallId"), time.time())
            res = e.get("result") or {}
            sc = res.get("structuredContent")
            sc = sc if isinstance(sc, dict) else {}
            bad = e.get("isError") or (sc.get("exit_code") not in (None, 0))
            out = "".join(x.get("text", "") for x in (res.get("content") or []) if isinstance(x, dict)) if isinstance(res, dict) else str(res)
            tail = one_line(out.strip().splitlines()[-1] if out.strip() else "", 70)
            mark = c("red", "✗") if bad else c("grn", "✓")
            if bad or e.get("toolName") == "bash": say(f"  {mark} {dur:4.1f}s  {c('dim', tail)}")
        elif t == "turn_end":
            m = e.get("message") or {}
            out_tokens += (m.get("usage") or {}).get("output", 0)
            txt = "".join(x.get("text", "") for x in (m.get("content") or []) if isinstance(x, dict) and x.get("type") == "text")
            if txt.strip(): last_text = txt.strip()
        elif t == "agent_settled" and e.get("aborted"):
            say(c("ylw", "aborted (loop police or timeout)"))

    except Exception as ex:  # a feed bug must never kill the agent behind it
        say(f"(feed: skipped an event: {ex})")

el = time.time() - t0
say(f"done in {int(el // 60)}m{int(el % 60):02d}s  tools {tools}  output {out_tokens} tok  thinking ~{thinking // 4} tok")
if last_text:
    for l in last_text.splitlines()[-6:]:
        if l.strip(): say(c("dim", "│ ") + one_line(l, 110))
