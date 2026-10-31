# Makes sure llama-swap on :8080 is serving $Alias (a model id from llama-swap's config.yaml).
# llama-swap runs one model at a time and swaps by model name, so every launcher just calls this with its model id.
# Set PI_LLAMA_SWAP to your start-llama-swap.bat if it is not at C:\llama-swap\start-llama-swap.bat.
param([Parameter(Mandatory)][string]$Alias)

$swap = if ($env:PI_LLAMA_SWAP) { $env:PI_LLAMA_SWAP } else { 'C:\llama-swap\start-llama-swap.bat' }

function Get-Listener { (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess }

$owner = Get-Listener
if ($owner -and (Get-Process -Id $owner -ErrorAction SilentlyContinue).ProcessName -ne 'llama-swap') {
  Write-Host "[pi-local] Something other than llama-swap is listening on :8080 - stop it first."
  exit 1
}

if (-not $owner) {
  Write-Host "[pi-local] Starting llama-swap..."
  Start-Process cmd.exe -ArgumentList '/c', "`"$swap`"" -WindowStyle Minimized
  for ($i = 0; $i -lt 30 -and -not (Get-Listener); $i++) { Start-Sleep 1 }
  if (-not (Get-Listener)) { Write-Host "[pi-local] llama-swap did not start - run $swap to see why."; exit 1 }
}

$running = try { (Invoke-RestMethod http://127.0.0.1:8080/running -TimeoutSec 5).running | ? { $_.state -eq 'ready' } | % model } catch { @() }
if ($running -contains $Alias) { exit 0 }
Write-Host "[pi-local] Loading $Alias (llama-swap)..."
# /upstream/<model>/health starts or swaps to the model and answers once it is ready (healthCheckTimeout in config.yaml)
for ($try = 0; $try -lt 3; $try++) {
  try {
    if ((Invoke-WebRequest "http://127.0.0.1:8080/upstream/$Alias/health" -UseBasicParsing -TimeoutSec 900).StatusCode -eq 200) { exit 0 }
  } catch { $why = $_.Exception.Message; Start-Sleep 3 }
}
Write-Host "[pi-local] $Alias did not come up ($why) - see http://127.0.0.1:8080/ui logs."
exit 1
