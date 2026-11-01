# Tuning for 12 GB of VRAM

## Rule: no spill

With `--fit off --gpu-layers 99`, llama.cpp puts everything on the GPU. If the KV cache plus compute buffers don't fit,
Windows quietly pages into shared (system) memory, and decoding drops from ~40 tok/s to 1–9 tok/s. The model still
"works", just very slowly.

How to find your real limit:
1. Pick a context size and cache type and start the server.
2. Fill the context to ~85–90% (e.g. send a long file) and measure decode speed at that depth.
3. Watch Task Manager → GPU → **Shared GPU memory**. If it grows ~1 GB over its idle value, you spilled.
4. Near the edge, the same config can spill on one run and not on the next. Leave ~0.3 GB headroom.

Measured limits (desktop using ~0.6–1 GB of VRAM):

| Model | KV q8_0 | KV q4_0 |
|---|---|---|
| Swift / Qwen3.8 27B IQ2_XS (8.8 GB) | 40K | 64K (48K when the desktop held 1.4 GB) |
| Swift 27B IQ3_XXS (10.4 GB) | 16K | 22K |
| Ornith 9B Q8_0 (9.8 GB) | 80K (11.78 GB at 68K deep) | 96K |

On Linux (Lubuntu, desktop ~0.3 GB of VRAM; ROCm fails the allocation instead of spilling, so "fits" = loads and a
~90% fill shows no GTT growth in `/sys/class/drm/card*/device/mem_info_gtt_used`):

| Model | KV q8_0 | KV q4_0 |
|---|---|---|
| Swift 27B IQ2_XS | | 64K (11.0 GB at 52K deep) |
| Ornith 9B Q8_0 | 96K loads (12.0 GB, very tight) | 160K loads (12.2 GB, very tight) |
| Ornith 9B Q6_K (7.0 GB) | **160K** (11.6 GB at 138K deep, 23.9 tok/s) | **256K** (12.1 GB at 236K deep, 16.2 tok/s) |

Always use `--parallel 1`: llama-server's default 4 slots each get MTP draft and compute buffers.

## The desktop's share of VRAM

`dwm.exe` (the Windows compositor) holds VRAM for **every display Windows thinks is attached**, including virtual
ones. On the test PC, a Parsec virtual display at 4K pushed dwm to ~1.5 GB, and 64K of context on the 27B spilled.
After disabling the "Parsec Virtual Display Adapter" devices in Device Manager and rebooting, dwm used 0.64 GB.
dwm keeps its memory until you sign out or reboot.

Check per-process VRAM in PowerShell:

```powershell
(Get-Counter '\GPU Process Memory(*)\Dedicated Usage').CounterSamples | ? CookedValue -gt 50MB |
  % { '{0,-16} {1,6:N0} MB' -f (Get-Process -Id ($_.InstanceName -split '_')[1]).ProcessName, ($_.CookedValue/1MB) }
```

## Speed flags that mattered

- `--spec-type draft-mtp --spec-draft-n-max 2`: +40–60% decode on both models. n-max 3 was no faster. On the 27B,
  adding ngram lookup made it slower.
- ROCm vs Vulkan on gfx1031: prompt reading 157–162 vs 106–123 tok/s, decode 35–39 vs 22–24 tok/s.
- On the 27B, `-ub 1024` hurt prompt speed. Leave the defaults.
- `--chat-template-kwargs "{\"reasoning_effort\":\"medium\"}"` on the 27B. Its template defaults to xhigh for any
  client that sends no level. Pi sends its own level per request, which overrides this.

## Pi settings that matter

- **Thinking levels.** Pi's `qwen` thinking format sends a top-level `enable_thinking` that llama-server ignores, so
  "off" still thinks. Use `thinkingFormat: "chat-template"` with `chatTemplateKwargs`, as in `pi-config/models.json`.
  Only the Qwen3.8-27B template has real effort levels. Ornith is on/off plus a token budget (`thinkingBudgets`).
- **`$var` is mandatory.** Every object value in `chatTemplateKwargs` needs a `$var`. Without it, Pi rejects the whole
  models.json and every local model disappears. Run `pi --list-models` after each edit.
- **Compaction for 48K.** Reserve 10240 and keep-recent 10000 start compaction at ~39K. Exec sessions start at 8–12K,
  and the largest single reply seen was ~6K tokens.
