# Shared by the pi-* launchers (sourced, not run). Finds the prompts, makes sure llama-swap serves a model, runs pi.
# Per-machine settings go in ~/.config/pi-local/env (sourced if present), e.g. on a laptop that uses another PC's models:
#   PI_REMOTE_SWAP=1                                  # llama-swap runs elsewhere (tunnel on :8080); don't try to start it
#   PI_EXTRA_TOOLS=firecrawl_search,firecrawl_scrape  # appended to the planner/reviewer tool lists
#   PI_EXCLUDE_TOOLS='ssh-*,call_model,mcp__*'        # passed as --exclude-tools to every role ...
#   PI_EXEC_EXCLUDE_TOOLS='ssh-*,call_model'          # ... except pi-exec, if this is set
#   PI_PLAN_MODEL=strata/qwen3.8-flash-next-gyro-s     # Pi provider/id for pi-plan ...
#   PI_PLAN_THINKING=xhigh / PI_REVIEW_THINKING=xhigh  # thinking level for pi-plan / the reviewers (default medium / low)
#   PI_PLAN_SWAP_ID=qwen3.8-flash-next-gyro-s          # ... and the llama-swap id that serves it
#   PI_REVIEW_MODEL=... PI_REVIEW_SWAP_ID=...          # the same for pi-review and pi-code-review
#   PI_EXEC_MODEL=... PI_EXEC_SWAP_ID=...              # the same for pi-exec
#   PI_*_SWAP_ID=none                                  # the role runs on a cloud model: load nothing in llama-swap
_here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
[ -f "${PI_LOCAL_ENV:-$HOME/.config/pi-local/env}" ] && source "${PI_LOCAL_ENV:-$HOME/.config/pi-local/env}"
# Prompts: $PI_PROMPTS, else next to the launchers (installed layout), else ../prompts (running from the repo).
if [ -n "${PI_PROMPTS:-}" ]; then PROMPTS="$PI_PROMPTS"
elif [ -f "$_here/planner.md" ]; then PROMPTS="$_here"
else PROMPTS="$_here/../prompts"; fi
SWAP="${PI_SWAP_URL:-http://127.0.0.1:8080}"

prompt_args() {  # prompt_args <role>.md -> sets P to --append-system-prompt for local-session, environment and the role
  local f; P=()
  for f in local-session.md environment.md "$1"; do
    [ -f "$PROMPTS/$f" ] || { echo "[pi-local] missing $PROMPTS/$f" >&2; return 1; }
    P+=(--append-system-prompt "$PROMPTS/$f")
  done
  [ -n "${PI_EXCLUDE_TOOLS:-}" ] && P+=(--exclude-tools "$PI_EXCLUDE_TOOLS")
  return 0
}

tools() {  # tools <comma list> -> the list plus PI_EXTRA_TOOLS
  if [ -n "${PI_EXTRA_TOOLS:-}" ]; then echo "$1,$PI_EXTRA_TOOLS"; else echo "$1"; fi
}

ensure_server() {  # ensure_server <llama-swap model id>; "none" = a cloud model, nothing to load
  local id="$1" i why
  [ "$id" = none ] && return 0
  if ! curl -sf -m 3 "$SWAP/v1/models" >/dev/null; then
    if [ -n "${PI_REMOTE_SWAP:-}" ]; then
      echo "[pi-local] Nothing answers on $SWAP. On the model PC: systemctl --user start llama-swap laptop-link"; return 1
    fi
    if ss -ltn 2>/dev/null | grep -q '127.0.0.1:8080 \|\*:8080 \|0.0.0.0:8080 '; then
      echo "[pi-local] Something other than llama-swap is listening on :8080 - stop it first."; return 1
    fi
    echo "[pi-local] Starting llama-swap (systemctl --user start llama-swap)..."
    systemctl --user start llama-swap || return 1
    for i in $(seq 30); do curl -sf -m 2 "$SWAP/v1/models" >/dev/null && break; sleep 1; done
    curl -sf -m 2 "$SWAP/v1/models" >/dev/null || { echo "[pi-local] llama-swap did not start - see: journalctl --user -u llama-swap"; return 1; }
  fi
  curl -sf -m 5 "$SWAP/running" | python3 -c 'import json,sys; sys.exit(0 if any(m.get("model")==sys.argv[1] and m.get("state")=="ready" for m in json.load(sys.stdin).get("running",[])) else 1)' "$id" 2>/dev/null && return 0
  echo "[pi-local] Loading $id (llama-swap)..."
  # /upstream/<model>/health starts or swaps to the model and answers once it is ready (healthCheckTimeout in config.yaml)
  for i in 1 2 3; do
    curl -sf -m 900 -o /dev/null "$SWAP/upstream/$id/health" && return 0
    why=$?; sleep 3
  done
  echo "[pi-local] $id did not come up (curl exit $why) - see $SWAP/ui logs."; return 1
}

run_pi() {  # run_pi <label> <timeout seconds, 0 = none> <pi args...>
  # Interactive: plain pi, no time limit. With -p (or under pi-loop, PI_FEED=1): hard time limit, and under pi-loop
  # the JSON event stream is shown as one line per action (pi-feed.py) and saved to PLAN.loop/<time>-<label>.jsonl.
  local label="$1" t="$2" a batch=; shift 2
  for a in "$@"; do case "$a" in -p|--print) batch=1 ;; esac; done
  [ -n "$batch" ] || exec pi "$@"
  if [ -n "${PI_FEED:-}" ]; then
    mkdir -p PLAN.loop
    local log="PLAN.loop/$(date +%m%d-%H%M%S)-$label.jsonl" rc
    if [ "$t" -gt 0 ]; then timeout -k 15 "$t" pi --mode json "$@" < /dev/null; else pi --mode json "$@" < /dev/null; fi \
      | python3 "$_here/pi-feed.py" "$label" "$log"
    rc=${PIPESTATUS[0]}
  else
    if [ "$t" -gt 0 ]; then timeout -k 15 "$t" pi "$@" < /dev/null; else pi "$@" < /dev/null; fi
    rc=$?
  fi
  [ "$rc" = 124 ] && echo "[pi-local] $label stopped: time limit ${t}s reached"
  return "$rc"
}
