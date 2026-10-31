@echo off
REM Unloads the model llama-swap is running (frees VRAM). llama-swap keeps listening; the next launcher loads one again.
powershell -NoProfile -Command "try { Invoke-RestMethod -Method Post http://127.0.0.1:8080/api/models/unload -TimeoutSec 60 | Out-Null; Write-Host '[pi-stop] model unloaded.' } catch { Write-Host '[pi-stop] llama-swap not running.' }"
exit /b 0
