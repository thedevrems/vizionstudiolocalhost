# Vérifie la base FiveM, démarre la base de données puis lance FXServer
. "$PSScriptRoot\lib.ps1"

Invoke-Main {
    $Host.UI.RawUI.WindowTitle = 'FiveM localhost'
    Write-Title 'Démarrage du serveur FiveM (localhost)'
    $settings = Get-KitSettings

    Write-Step 'Vérifications'
    $fxserver = Get-FxServerPath
    if (-not (Test-Path $fxserver)) { Stop-Kit "FXServer n'est pas installé : lance d'abord 1-INSTALLER.bat." }
    Write-Ok "FXServer build $(Get-InstalledBuild)"
    Show-PathWarnings

    $cfgFiles = @(Get-CfgFiles (Find-ServerCfg $settings))
    if (-not (Test-Path (Join-Path $ServerDataDir 'resources'))) {
        Stop-Kit 'Dossier server-data\resources introuvable : copie le dossier resources de ta base (README, étape 4).'
    }
    Write-Ok "Base trouvée : server-data\$($settings.ServerCfg)"

    $gamePort = Get-GamePort $cfgFiles
    if (Test-Port $gamePort) { Stop-Kit "Le port $gamePort est déjà utilisé : un serveur tourne déjà ? Ferme-le puis relance." }

    # Lignes absentes des .cfg de la base : elles iront dans kit-localhost.cfg, chargé avant server.cfg
    $extraLines = @()

    $license = Find-CfgSetting $cfgFiles $LicensePattern
    $key = if ($settings.LicenseKey) { $settings.LicenseKey } elseif ($license) { $license.Value }
    if (-not (Test-LicenseKey $key)) {
        Stop-Kit 'Clé de licence manquante : colle-la dans config.ini (LICENSE_KEY=...). Voir README, étape 1.'
    }
    $extraLines += @(Use-CfgValue $settings $license $LicensePattern 'sv_licenseKey' $key)
    Write-Ok 'Clé de licence présente'

    if (Test-UsesDatabase $cfgFiles) {
        Write-Step 'Base de données'
        $connection = Find-CfgSetting $cfgFiles $ConnectionPattern
        Complete-DbName $settings $connection
        Start-Database $settings
        Initialize-Database $settings
        $tables = Get-DbTableCount $settings
        Write-Ok "Base '$($settings.DbName)' prête ($tables tables)"
        if ($tables -eq 0) { Write-Warn 'La base est vide : importe le SQL de ta base avec 3-IMPORTER-SQL.bat (README, étape 5).' }

        $connectionString = New-ConnectionString $settings $(if ($connection) { $connection.Value })
        $extraLines += @(Use-CfgValue $settings $connection $ConnectionPattern 'set mysql_connection_string' $connectionString)
    } else {
        Write-Info 'Aucune ressource SQL détectée (oxmysql, mysql-async...) : base de données ignorée.'
    }

    if ($settings.ClearCache) {
        Remove-Item (Join-Path $ServerDataDir 'cache') -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok 'Cache du serveur vidé'
    }

    $fxArgs = @()
    $kitCfg = Join-Path $ServerDataDir $KitCfgName
    if ($extraLines) {
        $header = '# Fichier genere par 2-DEMARRER.bat a partir de config.ini - ne pas modifier'
        Write-Text $kitCfg ((@($header) + $extraLines) -join "`r`n")
        $fxArgs += '+exec', $KitCfgName
    } elseif (Test-Path $kitCfg) {
        Remove-Item $kitCfg
    }
    $fxArgs += '+exec', $settings.ServerCfg

    Write-Title 'Lancement du serveur'
    Write-Info "Pour jouer : ouvre FiveM, appuie sur F8 et tape   connect 127.0.0.1:$gamePort"
    Write-Info '             (ou double-clique sur REJOINDRE-LE-SERVEUR.bat)'
    Write-Info 'Pour arrêter : tape   quit   dans cette fenêtre'
    Write-Host ''

    Push-Location $ServerDataDir
    try {
        do {
            & $fxserver @fxArgs
            Write-Host ''
            $again = Read-Host 'Serveur arrêté. Relancer ? (O/N)'
        } while ($again -match '^(o|oui|y|yes)$')
    } finally {
        Pop-Location
    }
}
