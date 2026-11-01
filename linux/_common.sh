# Shared by the pi-* launchers (sourced, not run). Finds the prompts and makes sure llama-swap serves $1.
# Prompts: $PI_PROMPTS, else next to the launchers (installed layout), else ../prompts (running from the repo).
_here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
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
}

ensure_server() {  # ensure_server <llama-swap model id>
  local id="$1" i why
  if ! curl -sf -m 3 "$SWAP/v1/models" >/dev/null; then
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
