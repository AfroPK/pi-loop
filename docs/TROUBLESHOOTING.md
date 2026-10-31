# Troubleshooting

## Loops

Local reasoning models sometimes repeat themselves in thinking or retry the same tool call.
[pi-loop-police](https://www.npmjs.com/package/pi-loop-police) detects this and aborts the run with recovery advice.

**Bug in 1.14.1:** the recovery message is sent while Pi still counts the aborted run as streaming. It becomes a
steer into a dying run and gets dropped, and the session just stops with "Operation aborted". The patch in
`patches/` holds the recovery and sends it on `agent_settled` as a new run. It keeps the escalation state and gives up
after 5 back-to-back loops.

```bash
pi install npm:pi-loop-police@1.14.1          # Pi installs packages under ~/.pi/agent/npm/node_modules
cd ~/.pi/agent/npm/node_modules/pi-loop-police
patch -p1 < /path/to/repo/patches/pi-loop-police-1.14.1-recovery.patch
```

Pin the version (`npm:pi-loop-police@1.14.1` in settings.json). An update overwrites the patch.

Changing sampling didn't help. A replay of real looped contexts across four sampling settings gave 0/12 loops in every
arm, so the loops are rare and random. Fix the recovery, not the sampler.

## Very slow output (1–9 tok/s)

You spilled out of VRAM. See [TUNING.md](TUNING.md): lower `--ctx-size`, or free desktop VRAM (virtual displays,
GPU-accelerated apps).

## "did not come up" from ensure-server

Open http://127.0.0.1:8080/ui and read the model's log. Common causes: a wrong path in a `config.yaml` macro, or a
crashed llama-server that still holds VRAM. Stop it from the llama-swap UI or with `pi-stop`.

## Pi waits forever with -p

stdin is still open. Redirect it: `pi-plan -p "task" < /dev/null` (Git Bash) or `<nul` (cmd).

## The planner wrote code instead of a plan

The model isn't fit for the planner role (see [MODELS.md](MODELS.md)). Some models ignore role prompts under tool
pressure. Use a dense model of ~27B, or stronger.
