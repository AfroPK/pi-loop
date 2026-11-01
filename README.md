# Local plan → review → exec for the Pi coding agent

A coding-agent workflow that runs **entirely on local inference** on one 12 GB GPU. It uses
[llama.cpp](https://github.com/ggml-org/llama.cpp), [llama-swap](https://github.com/mostlygeek/llama-swap) and the
[Pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent). It needs no cloud API and no API keys.

A stronger "thinking" model writes a verified plan. A fresh session of the same model reviews it. Then a small, fast
coder model carries it out step by step. Both models fit **fully in VRAM**, and llama-swap swaps between them on demand.

```
 pi-pe "task"
   │
   ├─ pi-plan    Swift 1.5 27B (IQ2_XS + MTP, 48K ctx)  thinking medium  → PLAN.md, PLAN.files/, PLAN.notes.md
   ├─ pi-review  Swift 1.5 27B, fresh session            thinking medium  → appends ### REVIEW CORRECTIONS
   ├─ pi-exec    Ornith 1.5 9B (Q8_0 + MTP, 80K ctx)     thinking low     → edits code, ticks boxes, runs Verify
   └─ pi-code-review  Swift 27B, fresh session          thinking medium  → PLAN.review.md; proven bugs become
                                                                           a fix slice at the top of PLAN.next.md
                 ▲ llama-swap swaps models (~30–40 s) — only one fits in 12 GB at a time
```

Context sizes above are the Windows ones. On Linux the desktop takes far less VRAM: Swift runs 64K and Ornith Q6_K
runs 160K (see [Linux](#linux)). `pi-code-review` has Linux launchers only so far.

After `pi-exec`, **`pi-code-review`** reviews only what the executor changed (a diff against the `PLAN.base/` snapshot
`pi-exec` takes), reruns Verify and the tests, and probes what the tests miss. Every finding must come with a proof
script and its real output (kept in `PLAN.review.files/`), at most 3 correctness findings, no style. Proven bugs become
a `## Slice: fixes from code review` that plain `pi-plan` picks up next; it never edits code itself. First test, on a
Go game slice whose Verify all passed: it found a real pass-counter bug, missed a ko-rule bug, no false findings.

## Why this works on a small GPU

- **The two roles need different models.** In tests on this machine, small and MoE models wrote the code themselves
  instead of a plan, or got stuck in tool loops, when given the planner role. A dense 27B at 2-bit planned reliably.
  The 9B coder was the fastest model that executed those plans correctly.
- **Both models use multi-token prediction (MTP).** Each GGUF has its own MTP head, so llama.cpp's `draft-mtp` speeds up
  decoding with no separate draft model: 27B ~41 tok/s, 9B ~62 tok/s.
- **Plans are made safe for a small executor.** The prompts force small slices, code written once into `PLAN.files/`,
  a rehearsal in a scratch copy, and a mandatory log/self-test for every feature, so "done" means proven.
  See [docs/WORKFLOW.md](docs/WORKFLOW.md).

## Tested hardware

| | |
|---|---|
| GPU | AMD RX 6750 XT 12 GB (RDNA2, gfx1031) on ROCm (HIP) |
| OS | Windows 11 with Git Bash as Pi's shell, and Lubuntu 26.04 (ROCm 7.1 from the Ubuntu archive) |
| CPU / RAM | Ryzen 7 5700X, 32 GB (both models run fully in VRAM, so these barely matter) |

NVIDIA 12 GB cards should work with a CUDA llama.cpp build and the same flags. That's untested here, so measure the
context limits yourself (see [docs/TUNING.md](docs/TUNING.md)).

## Quick start

1. **Install the tools.**
   - Node.js 22+ and Git for Windows.
   - Pi: `npm i -g @earendil-works/pi-coding-agent`
   - A llama.cpp `llama-server` build for your GPU. For RX 6000 cards on Windows, see
     [docs/HARDWARE.md](docs/HARDWARE.md).
   - [llama-swap](https://github.com/mostlygeek/llama-swap/releases): unzip it to `C:\llama-swap`.
2. **Download the models** (GGUF, from Hugging Face):
   - Planner/reviewer: `ukisai/Swift-1.5-Qwen3.8-27B-GSQ-RCO-GGUF`, file `...-IQ2_XS-mtp.gguf` (8.8 GB)
   - Executor: `ornith-ai/Ornith-1.5-9B-GGUF`, file `Ornith-1.5-9B-Q8_0.gguf` (9.8 GB)
3. **llama-swap.** Copy `llama-swap/config.yaml` and `start-llama-swap.bat` to `C:\llama-swap`, then set the `server`
   and `models` macros at the top of `config.yaml` to your paths.
4. **Pi config.** Merge `pi-config/models.json` into `%USERPROFILE%\.pi\agent\models.json`, and the relevant keys of
   `settings.example.json` into `%USERPROFILE%\.pi\agent\settings.json`. On Windows, also set `"shellPath"` to
   Git's `bash.exe`. Run `pi --list-models`: both `swift27-xs-64k` and `ornith9b-q8` must appear. If a models.json
   edit is invalid, every local model disappears from that list.
5. **Launchers and prompts.** Copy everything in `launchers/` and `prompts/` into one folder on your PATH
   (e.g. `%USERPROFILE%\.pi`). Rename `environment.example.md` to `environment.md` and edit it for your PC.
   The prompts tell the models to check API docs with `firecrawl_search` / `firecrawl_scrape` when unsure. That's an
   optional web-search MCP (e.g. a self-hosted Firecrawl). If you have one, add both names to `--tools` in
   `pi-plan.cmd` and `pi-review.cmd`. Without it, the models fall back to reading code and running small experiments.
6. **Recommended:** install `pi-loop-police@1.14.1` and apply `patches/pi-loop-police-1.14.1-recovery.patch`
   (see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)).
7. **Run it** in a project folder:

```bat
pi-pe "Add a --json flag to report.py that prints the summary as JSON, with a unittest"
```

Or run each step yourself, so you can read the plan before anything changes:

```bat
pi-plan "task"      &REM writes PLAN.md (add -p for no UI)
pi-review           &REM appends corrections
pi-exec             &REM carries it out (snapshots the project to PLAN.base/ first)
pi-code-review      &REM Linux: reviews what pi-exec changed; proven bugs -> PLAN.review.md + fix slice in PLAN.next.md
pi-plan             &REM no task = plan the next slice from PLAN.next.md
pi-stop             &REM unload the model, free VRAM
```

The first launcher you run starts llama-swap for you. To run it by hand, use `start-llama-swap.bat`
(web UI: http://127.0.0.1:8080/ui).

## Linux

`linux/` has bash versions of the launchers. Tested on Lubuntu 26.04 + ROCm 7.1 (see [docs/HARDWARE.md](docs/HARDWARE.md)).

1. Node.js 22+ (any install; a user-local tarball works), then `npm i -g @earendil-works/pi-coding-agent`.
2. llama-server built for your GPU, and [llama-swap](https://github.com/mostlygeek/llama-swap/releases) (`linux_amd64` tarball).
3. Copy `linux/llama-swap/config.yaml` next to llama-swap and edit its `server` / `models` macros. Install
   `linux/llama-swap/llama-swap.service` to `~/.config/systemd/user/` (fix the paths), then
   `systemctl --user enable --now llama-swap`. The launchers start it if it's stopped.
4. Pi config as in step 4 above, in `~/.pi/agent/`. On Linux Swift fits 64K, so set its `contextWindow` to 65536
   and drop the 48K `modelOverrides` entry.
5. `cp linux/environment.example.md prompts/environment.md` and edit it (gitignored), then link the launchers onto
   your PATH: `for f in pi-plan pi-review pi-exec pi-code-review pi-pe pi-stop; do ln -s "$PWD/linux/$f" ~/.local/bin/; done`.
   They find the prompts in `../prompts` (or set `PI_PROMPTS`).
6. loop-police and its patch: same as step 6.

Measured on Linux (RX 6750 XT, ROCm 7.1, MTP n2, thinking on, through llama-swap):

| Role | Model | Context | Decode short | Decode when nearly full |
|---|---|---|---|---|
| Planner / reviewers | Swift 1.5 27B IQ2_XS | 64K q4_0 | 37.6 tok/s | 21.6 at 52K |
| Executor | Ornith 1.5 9B **Q6_K** (7.0 GB) | 160K q8_0 | 77.0 tok/s | 23.9 at 138K |
| Executor, max context | Ornith 1.5 9B Q6_K | 256K q4_0 | ~75 tok/s | 16.2 at 236K |
| Executor, faster prefill | Ornith 1.5 9B Q8_0 | 80K q8_0 | 68.5 tok/s | 35.2 at 65K |

The Q6_K decodes faster than the Q8_0 and fits twice the context, but prefills ~30% slower (735 vs 1038 tok/s).
`linux/llama-swap/config.yaml` uses it under the same `ornith9b-q8` id, so Pi and the launchers need no changes;
set that model's `contextWindow` to 163840 in models.json. Download `Ornith-1.5-9B-Q6_K.gguf` from the same repo.

## Repo layout

| Path | What |
|---|---|
| `linux/` | bash launchers (incl. `pi-code-review`), Linux `environment.example.md`, llama-swap config + systemd user unit |
| `launchers/` | Windows: `pi-plan`, `pi-review`, `pi-exec`, `pi-pe`, `pi-stop`, plus `ensure-server.ps1` (starts llama-swap and loads a model by id) |
| `prompts/` | `planner.md`, `reviewer.md`, `executor.md`, `code-reviewer.md` (role rules), `environment.example.md` (your machine's facts), `local-session.md` |
| `llama-swap/` | `config.yaml` with both models' tuned llama-server flags |
| `pi-config/` | Pi provider/model definitions (thinking-level mapping) and compaction settings |
| `patches/` | Fix for pi-loop-police's loop recovery silently ending the session |
| `docs/` | [WORKFLOW](docs/WORKFLOW.md) · [MODELS](docs/MODELS.md) (benchmarks, what failed) · [TUNING](docs/TUNING.md) (VRAM, context) · [HARDWARE](docs/HARDWARE.md) · [TROUBLESHOOTING](docs/TROUBLESHOOTING.md) |

## Using other models

Model IDs live in three places, and they must match:
- `MODEL_ID` / `PI_MODEL` at the top of each launcher;
- the model key in llama-swap's `config.yaml`;
- the `id` in Pi's `models.json`.

The prompts state each model's context size, so update `planner.md`, `reviewer.md` and `executor.md` too. Before you
trust a new planner, run it on a small task in an empty folder. It must write only `PLAN.*` files. If it writes the
code itself, it isn't a planner. [docs/MODELS.md](docs/MODELS.md) lists what was tried and why it failed.

## License

MIT for the scripts and prompts in this repo. The patch applies to pi-loop-police (MIT). The models have their own licenses.
