# llama.cpp on an RX 6000 card (gfx1031) under Windows

The official llama.cpp `win-rocm` release bundles a ROCm runtime that doesn't list gfx1031 (RX 6700/6750 XT) as a
device. What worked:

1. Download the official llama.cpp release zip for Windows ROCm (tested: b11869, `win-rocm-10.0`).
2. Get the ROCm **10.2** runtime DLLs and `.kpack` kernel files from a TheRock ROCm build that supports gfx1031, and
   copy them over the release's own (`amdhip64_7.dll`, `amd_comgr.dll`, `hipblas.dll`, `libhipblaslt.dll`, ...).
3. Run `llama-server --list-devices`. Your card must show up.

Notes:
- Don't use `--no-host` on ROCm.
- Vulkan works without any of this and fits a bit more context, but it's ~40% slower here. It's a fine starting point
  if the ROCm swap fails.
- RX 6800/6900 (gfx1030) and RX 7000 (gfx11xx) cards are officially supported by ROCm, so the release build may work
  as is.
- NVIDIA: use the CUDA release. All other flags are the same.
