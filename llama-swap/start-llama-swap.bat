@echo off
REM llama-swap on :8080 - one endpoint for every local model (config.yaml). Web UI: http://127.0.0.1:8080/ui
REM ensure-server.ps1 starts this when a launcher needs a model; it can also run on its own.
REM --watch-config reloads on save, which also unloads the running model.
title llama-swap
"%~dp0llama-swap.exe" --config "%~dp0config.yaml" --listen 127.0.0.1:8080 --watch-config
if errorlevel 1 pause
