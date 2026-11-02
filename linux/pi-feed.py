#!/usr/bin/env python3
"""pi-feed.py LABEL [LOG]: turn `pi --mode json` events on stdin into a readable live feed:
the agent's thinking (dim, 💭) and replies (│) as they stream, plus one line per tool call and its result.
PI_FEED_THINKING=full (default) | short (first line of each thought) | off. Raw events go to LOG if given."""
import json, os, shutil, sys, textwrap, time

label = sys.argv[1] if len(sys.argv) > 1 else "pi"
log = open(sys.argv[2], "w") if len(sys.argv) > 2 else None
tty = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
C = {"dim": "\033[2m", "red": "\033[31m", "grn": "\033[32m", "ylw": "\033[33m", "cyn": "\033[36m", "off": "\033[0m"}
def c(k, s): return f"{C[k]}{s}{C['off']}" if tty else s

t0 = time.time()
def stamp(): s = int(time.time() - t0); return f"{s // 60:2d}:{s % 60:02d}"
def say(msg):
    global sys
    try: print(f"{c('dim', stamp())} {c('cyn', f'[{label}]')} {msg}", flush=True)
    except (BrokenPipeError, OSError):   # the viewer went away: keep consuming events so the agent finishes
        sys.stdout = open(os.devnull, "w")

MODE = os.environ.get("PI_FEED_THINKING", "full")
WIDTH = max(40, shutil.get_terminal_size((120, 40)).columns - 18)   # room for "mm:ss [label] "
buf = {"thinking": "", "text": ""}
shown_short = False

def emit(kind, line):
    """Print one finished line of thinking or reply text, wrapped to the terminal."""
    global shown_short
    if not line.strip(): return
    if kind == "thinking":
        if MODE == "off": return
        if MODE == "short":
            if shown_short: return
            shown_short = True
        for w in textwrap.wrap(line, WIDTH) or [""]: say(c("dim", "💭 " + w))
    else:
        for w in textwrap.wrap(line, WIDTH) or [""]: say("│ " + w)

def feed(kind, delta):
    buf[kind] += delta
    while "\n" in buf[kind]:
        line, buf[kind] = buf[kind].split("\n", 1)
        emit(kind, line)

def flush(kind):
    global shown_short
    if buf[kind]: emit(kind, buf[kind]); buf[kind] = ""
    if kind == "thinking": shown_short = False

def one_line(s, n=90):
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1] + "…"

ICON = {"bash": "💻", "read": "📖", "write": "📝", "edit": "✏️ ", "grep": "🔍", "find": "🔎", "ls": "📂",
        "firecrawl_search": "🌐", "firecrawl_scrape": "🕸️ "}
def icon(tool): return ICON.get(tool, "🔧")

CWD = os.getcwd().rstrip("/")
def rel(x):
    """Show project paths relative to the project folder, and drop a leading 'cd <project> &&'."""
    x = str(x)
    for pre in (f"cd {CWD} && ", f"cd {CWD}; ", f"cd {CWD}\n"):
        if x.startswith(pre): x = x[len(pre):]
    return x.replace(CWD + "/", "").replace(CWD, ".")

def describe(tool, args):
    a = {k: rel(v) if isinstance(v, str) else v for k, v in (args or {}).items()}
    if tool == "bash": return one_line(a.get("command", ""), 80)
    if tool in ("read", "write", "edit"): return a.get("path") or a.get("file_path") or ""
    if tool in ("grep", "find", "ls"): return one_line(" ".join(str(v) for v in a.values()), 80)
    return one_line(json.dumps(a), 80)

thinking = out_tokens = tools = 0
turn_start = first_tok = None      # per model reply: when it was requested, when its first token arrived
gen_time = 0.0                     # total seconds spent generating (for the average tok/s)
# Live rate for pi-loop-tui (PI_FEED_LIVE=1): streamed pieces per second, scaled by this agent's measured
# tokens-per-piece ratio (exact counts arrive only at the end of each reply), sent as hidden \x1e lines.
LIVE = os.environ.get("PI_FEED_LIVE") == "1"
pieces = 0; all_pieces = 0; last_live = 0.0
# A long tool call (a big file being written) streams for minutes before the tool runs: say so after 3 s.
composing = None   # [tool name, start time, pieces at start, last report time]
def live(kind, rate=0.0, toks=0):
    try: print(f"\x1elive {label} {kind} {rate:.1f} {toks}", flush=True)
    except (BrokenPipeError, OSError): pass
last_text = ""
starts = {}
for line in sys.stdin:
    if log: log.write(line); log.flush()
    try:
        try: e = json.loads(line)
        except ValueError: continue
        t = e.get("type")
        msg = e.get("message") if isinstance(e.get("message"), dict) else None
        if LIVE and msg and msg.get("role") == "assistant" and msg.get("model"):
            mid = (msg.get("provider") + "/" if msg.get("provider") else "") + msg["model"]
            if mid != starts.get("_model"):
                starts["_model"] = mid
                try: print(f"\x1emodel {label} {mid}", flush=True)
                except (BrokenPipeError, OSError): pass
        if t == "turn_start":
            turn_start, first_tok = time.time(), None
            pieces = 0
            if LIVE: live("prompt")
        if t == "message_update":
            if first_tok is None: first_tok = time.time()
            ev = e.get("assistantMessageEvent") or {}
            et2 = ev.get("type", "")
            if et2 == "toolcall_start":
                composing = [ev.get("toolName", "tool"), time.time(), pieces, 0.0]
            elif et2 == "toolcall_end":
                composing = None
            if composing and time.time() - composing[1] > 3 and time.time() - composing[3] > 20:
                ratio = out_tokens / all_pieces if all_pieces and out_tokens else 1.12
                n_so_far = int((pieces - composing[2]) * ratio)
                flush("thinking"); flush("text")
                say(c("dim", f"✍️  {'still writing the' if composing[3] else 'writing a'} {composing[0]} call… ({n_so_far} tok{' so far' if not composing[3] else ''})"))
                composing[3] = time.time()
            if str(et2).endswith("_delta"):
                pieces += 1
                if LIVE and time.time() - last_live >= 0.5:
                    last_live = time.time()
                    ratio = out_tokens / all_pieces if all_pieces and out_tokens else 1.12
                    toks = pieces * ratio
                    live("call:" + composing[0] if composing else "gen", toks / max(time.time() - first_tok, 0.2), int(toks))
            et = ev.get("type")
            if et == "thinking_delta": thinking += len(ev.get("delta", "")); feed("thinking", ev.get("delta", ""))
            elif et == "thinking_end": flush("thinking")
            elif et == "text_delta": feed("text", ev.get("delta", ""))
            elif et == "text_end": flush("text")
        elif t == "tool_execution_start":
            if LIVE: live("tool")
            flush("thinking"); flush("text")
            tools += 1; starts[e.get("toolCallId")] = time.time()
            tn = e.get('toolName')
            say(f"{icon(tn)} {tn}  {describe(tn, e.get('args'))}")
        elif t == "tool_execution_end":
            dur = time.time() - starts.pop(e.get("toolCallId"), time.time())
            res = e.get("result") or {}
            sc = res.get("structuredContent")
            sc = sc if isinstance(sc, dict) else {}
            bad = e.get("isError") or (sc.get("exit_code") not in (None, 0))
            out = "".join(x.get("text", "") for x in (res.get("content") or []) if isinstance(x, dict)) if isinstance(res, dict) else str(res)
            tail = one_line(out.strip().splitlines()[-1] if out.strip() else "", 70)
            mark = "❌" if bad else "✅"
            if bad or e.get("toolName") == "bash": say(f"  {mark} {dur:4.1f}s  {c('dim', tail)}")
        elif t == "turn_end":
            m = e.get("message") or {}
            n = (m.get("usage") or {}).get("output", 0)
            out_tokens += n
            all_pieces += pieces
            if n and first_tok:
                g = max(time.time() - first_tok, 1e-3); gen_time += g
                pre = f"  prompt {first_tok - turn_start:4.1f}s" if turn_start else ""
                flush("thinking"); flush("text")
                say(c("ylw", f"⚡ {n / g:5.1f} tok/s  {n:5d} tok{pre}"))
            turn_start = first_tok = None
            txt = "".join(x.get("text", "") for x in (m.get("content") or []) if isinstance(x, dict) and x.get("type") == "text")
            if txt.strip(): last_text = txt.strip()
        elif t == "agent_settled" and e.get("aborted"):
            say(c("ylw", "aborted (loop police or timeout)"))

    except Exception as ex:  # a feed bug must never kill the agent behind it
        say(f"(feed: skipped an event: {ex})")

el = time.time() - t0
avg = f"  avg {out_tokens / gen_time:.1f} tok/s" if gen_time else ""
say(f"done in {int(el // 60)}m{int(el % 60):02d}s  tools {tools}  output {out_tokens} tok  thinking ~{thinking // 4} tok{avg}")
flush("thinking"); flush("text")
