# Ouvre FiveM et le connecte au serveur local
. "$PSScriptRoot\lib.ps1"

Invoke-Main {
    $settings = Get-KitSettings
    $cfg = Join-Path $ServerDataDir $settings.ServerCfg
    $port = if (Test-Path $cfg) { Get-GamePort @(Get-CfgFiles $cfg) } else { 30120 }

    if (-not (Test-Port $port)) {
        Write-Warn "Le serveur ne répond pas encore sur le port $port : lance 2-DEMARRER.bat et attends la fin du chargement."
    }
    Write-Ok "Ouverture de FiveM -> 127.0.0.1:$port"
    Start-Process "fivem://connect/127.0.0.1:$port"
}
