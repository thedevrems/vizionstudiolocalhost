# Installation / mise à jour : choix de la base de données, clé de licence, FXServer
. "$PSScriptRoot\lib.ps1"

Invoke-Main {
    $Host.UI.RawUI.WindowTitle = 'FiveM localhost - Installation'
    Write-Title 'Installation du kit localhost FiveM'
    Show-PathWarnings

    # Fichiers téléchargés depuis internet : on retire le blocage Windows
    Get-ChildItem $Root, $PSScriptRoot -File | Where-Object { $_.Extension -in '.ps1', '.bat' } | Unblock-File

    $settings = Get-KitSettings

    Write-Step 'Base de données : XAMPP ou Docker ?'
    $hasXampp  = Test-Path (Join-Path $settings.XamppPath 'mysql\bin\mysqld.exe')
    $hasDocker = [bool](Get-Command docker -ErrorAction SilentlyContinue)
    $status = { param($Found) if ($Found) { '(détecté sur ce PC)' } else { '(non installé)' } }
    Write-Info "[1] XAMPP   - le plus simple, MySQL directement sur Windows   $(& $status $hasXampp)"
    Write-Info "[2] Docker  - MariaDB isolée dans un conteneur + phpMyAdmin   $(& $status $hasDocker)"
    Write-Info 'Pas encore installé ? Suis le README, étape 2.'
    if ($settings.DbMode) { Write-Info "Choix actuel : $($settings.DbMode) (Entrée pour le garder)" }
    do {
        $mode = switch ("$(Read-Host 'Ton choix (1 ou 2)')".Trim()) {
            '1'     { 'xampp' }
            '2'     { 'docker' }
            ''      { $settings.DbMode }
        }
    } until ($mode)
    Set-ConfigValue 'DB_MODE' $mode
    $settings = Get-KitSettings
    Write-Ok "Base de données : $mode"
    if ($mode -eq 'xampp' -and -not $hasXampp) {
        Write-Warn "XAMPP introuvable dans $($settings.XamppPath) : installe-le (https://www.apachefriends.org) - README, étape 2A."
    }
    if ($mode -eq 'docker' -and -not $hasDocker) {
        Write-Warn 'Docker Desktop introuvable : installe-le (https://www.docker.com/products/docker-desktop) - README, étape 2B.'
    }

    Write-Step 'Clé de licence FiveM'
    if (Test-LicenseKey $settings.LicenseKey) {
        Write-Ok 'Clé déjà renseignée dans config.ini.'
    } else {
        Write-Info 'Crée ta clé sur https://portal.cfx.re (README, étape 1).'
        $key = "$(Read-Host 'Colle ta clé ici (Entrée pour le faire plus tard)')".Trim()
        if ($key) {
            Set-ConfigValue 'LICENSE_KEY' $key
            Write-Ok 'Clé enregistrée dans config.ini.'
        } else {
            Write-Warn 'Pas de clé pour le moment : mets-la dans config.ini (LICENSE_KEY=) avant de démarrer.'
        }
    }

    Write-Step 'Serveur FiveM (FXServer)'
    Install-Artifacts $settings

    Write-Step 'Test de la base de données'
    try {
        Complete-DbName $settings (Get-CfgConnection $settings)
        Start-Database $settings
        Initialize-Database $settings
        Write-Ok "Connexion OK - base '$($settings.DbName)' prête."
    } catch {
        Write-Warn "Base de données pas encore prête : $($_.Exception.Message)"
        Write-Warn 'Corrige le problème puis relance 1-INSTALLER.bat (README, étape 2).'
    }

    Write-Title 'Installation terminée - prochaines étapes'
    Write-Info '1. Copie ta base dans server-data\  (dossier resources + server.cfg)'
    Write-Info '2. Mets ses fichiers .sql dans sql\  puis lance 3-IMPORTER-SQL.bat'
    Write-Info '3. Lance 2-DEMARRER.bat'
    Write-Info 'Le tuto complet est dans README.md'
}
