# Model choice and benchmarks

All numbers were measured on an RX 6750 XT 12 GB (ROCm, llama.cpp b11869) in October 2026, mostly with 1–3 samples
per test. Treat them as directional.

## Current picks

| Role | Model | Quant / file | Context | Decode | Why |
|---|---|---|---|---|---|
| Planner, reviewer | Swift 1.5 (post-train of Qwen3.8-27B) | ISTA GSQ-RCO IQ2_XS + MTP, 8.8 GB | 48K q4_0 | ~41 tok/s short, ~31 at 37K | Only all-VRAM model that reliably writes a plan instead of the code; real low/medium/xhigh thinking levels; fewest runaways on trap prompts |
| Executor | Ornith 1.5 9B (post-train of Qwen3.5-9B) | Q8_0 with built-in MTP head, 9.8 GB | 80K q8_0 | ~62 tok/s | Ran the planner's plans 2/2 in 51–60 s, vs 159 s for Swift |

## Planner candidates

Test: `pi-plan -p` in an empty folder with a small CLI + unittest task. The planner must write only PLAN.md.

| Model | Result |
|---|---|
| Qwen3.8-27B ISTA IQ2_XS (dense) | PLAN.md only, 0 loops. Medium planned as well as xhigh and ~30% faster |
| Swift 1.5 27B IQ2_XS (dense) | PLAN.md only, 0 loops. Same quality as the ISTA 27B; on trap prompts 5/21 runaways vs 9/21, and ~half the tokens on ambiguous prompts |
| Ornith 1.5 9B Q8 | **Failed 2/2**: wrote the code itself; in one run a 202-call tool loop |
| Qwen3.6-35B-A3B (IQ3_XXS and AntiLoop) | **Failed**: ignored the PLAN.md-only rule and looped. A later run on stricter prompts did plan, but both overthink 7–9x vs Swift on reasoning tasks, and they don't fit fully in 12 GB |

Swift's card claims "58.5% fewer thinking tokens". That wasn't reproduced at this quant: +28% on short tasks and
about equal on agent tasks. It was chosen for loop resistance, not speed.

## Executor benchmark

5 graded tasks × 2 runs each, thinking low, with planted traps: a wrong anchor, wrong test expectations, a missing
vendored library that must become a Blocker, and a do-not-touch file.

| Model | Passed | Median per run | Notes |
|---|---|---|---|
| Qwen3.6-35B-A3B IQ3_XXS (experts in RAM) | 10/10 | 120 s | Best overall, but not all-VRAM |
| Qwen3.6-35B-A3B Q4_K_M | 9/10 | 150 s | Renamed a function to match a wrong anchor |
| Swift 27B IQ2_XS | 9/10 | 218 s | Wrote the Blocker, but still applied the breaking import |
| **Ornith 9B Q8** | 9/10 | 145 s | One run did `find /` over the whole disk; `executor.md` now forbids it and bounds every command |
| Swift 27B IQ3_XXS | 10/10 | 602 s | Most careful, but only 22K context fits; spilled to RAM and crawled |

Swapping models between plan and exec costs ~35–40 s each way. For one small task that's about what Ornith saves. For
exec-heavy jobs (many steps, test loops) the split wins. If you mostly run tiny tasks, point `pi-exec` at the planner
model too, and there's no swap.

## Also tried, not used

- **Nemotron 3.5 Bolt 74B-A9B** (experts in RAM): 16/16 on the reasoning set, but ~20 tok/s and 2–3x the tokens of
  Swift. Also ran `find /` and hung for hours.
- **Kaggle 2x T4, Qwen3.8-27B Q6_K** over a Cloudflare tunnel: fast enough, but quick tunnels drop requests after 120 s
  without bytes (HTTP 524) while a long prompt is still being read. That kills agent sessions.
