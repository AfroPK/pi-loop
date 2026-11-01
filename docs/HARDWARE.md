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

# llama.cpp on an RX 6000 card (gfx1031) under Linux

Tested on Lubuntu 26.04 with ROCm 7.1 from the Ubuntu archive (no AMD repo, no container, no DLL swaps):

```bash
sudo apt install hipcc libamdhip64-dev libhipblas-dev librocblas-dev rocm-cmake rocminfo rocm-smi
sudo usermod -aG render,video $USER      # then log out and back in
HSA_OVERRIDE_GFX_VERSION=10.3.0 rocminfo | grep gfx   # must list gfx1030
HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
  cmake -S llama.cpp -B llama.cpp/build-hip -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1030 -DCMAKE_BUILD_TYPE=Release
cmake --build llama.cpp/build-hip -j --target llama-server
```

- Ubuntu's rocBLAS ships gfx1030 kernels; `HSA_OVERRIDE_GFX_VERSION=10.3.0` lets gfx1031 use them. llama-swap sets it per model.
- **Flash-attention crash on ROCm 7.1:** `GGML_ASSERT(max_blocks_per_sm > 0) failed` in `ggml-cuda/fattn-common.cuh`.
  `hipOccupancyMaxActiveBlocksPerMultiprocessor` returns 0 for the head-size-256 tile kernel. Replacing the assert
  with a fallback to 1 fixes it; `test-backend-ops -o FLASH_ATTN_EXT` then passes. Re-apply after each `git pull`.
- Always run `--parallel 1`. The default 4 slots each get MTP draft and compute buffers, and Swift 64K runs out of VRAM.
- Measured on Linux (MTP n2, decode tok/s): Swift and Ornith fit fully in VRAM at 64K / 80K. ROCm beat Vulkan by
  ~30-60% on prompt processing and on MoE models with MTP; on Ornith without MTP, Vulkan decoded ~10% faster.
