# Importe les fichiers .sql du dossier sql\ dans la base du serveur
. "$PSScriptRoot\lib.ps1"

function Show-ResourceSqlFiles {
    $resources = Join-Path $ServerDataDir 'resources'
    $found = @(Get-ChildItem $resources -Filter *.sql -File -Recurse -ErrorAction SilentlyContinue)
    if (-not $found) { return }
    Write-Step "$($found.Count) fichier(s) .sql trouvé(s) dans tes resources (non importés automatiquement) :"
    $found | Select-Object -First 15 | ForEach-Object { Write-Info "- $($_.FullName.Substring($ServerDataDir.Length + 1))" }
    if ($found.Count -gt 15) { Write-Info '- ...' }
    Write-Info 'Si une ressource en a besoin, copie son .sql dans sql\ puis relance l''import.'
}

Invoke-Main {
    $Host.UI.RawUI.WindowTitle = 'FiveM localhost - Import SQL'
    Write-Title 'Import des fichiers SQL'
    $settings = Get-KitSettings

    $files = @(Get-ChildItem $SqlDir -Filter *.sql -File -Recurse | Sort-Object FullName)
    if (-not $files) {
        Show-ResourceSqlFiles
        Stop-Kit 'Aucun fichier .sql dans le dossier sql\ : mets-y les fichiers SQL de ta base (README, étape 5).'
    }
    Complete-DbName $settings (Get-CfgConnection $settings)

    # Un fichier qui contient "USE autre_base;" envoie ses tables dans une autre base
    $used = @($files | Select-String -Pattern '^\s*USE\s+`?([A-Za-z0-9_-]+)`?\s*;' |
        ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
    $others = @($used | Where-Object { $_ -ne $settings.DbName })
    if ($used.Count -eq 1 -and $others.Count -eq 1) {
        Write-Warn "Tes fichiers SQL utilisent la base '$($others[0])' (ligne USE), pas '$($settings.DbName)'."
        if ((Read-Host "Utiliser '$($others[0])' comme base du serveur ? (O/N)") -match '^(o|oui|y|yes)$') {
            Set-ConfigValue 'DB_NAME' $others[0]
            $settings.DbName = $others[0]
        }
    } elseif ($others) {
        Write-Warn "Tes fichiers SQL changent de base (USE $($others -join ', ')) : ces tables n'iront pas dans '$($settings.DbName)'."
    }

    Write-Step 'Base de données'
    Start-Database $settings
    Initialize-Database $settings
    $tables = Get-DbTableCount $settings
    Write-Ok "Base '$($settings.DbName)' : $tables tables actuellement"

    Write-Step "Fichiers à importer dans '$($settings.DbName)' (ordre alphabétique) :"
    $files | ForEach-Object { Write-Info "- $($_.FullName.Substring($SqlDir.Length + 1))" }
    if ($tables -gt 0) { Write-Warn 'La base contient déjà des tables : un 2e import peut provoquer des erreurs "already exists" ou des doublons.' }
    if ((Read-Host 'Lancer l''import ? (O/N)') -notmatch '^(o|oui|y|yes)$') {
        Write-Info 'Import annulé.'
        return
    }

    Write-Step 'Import'
    $failed = 0
    foreach ($file in $files) {
        $result = Import-SqlFile $settings $file.FullName
        if ($result.Code -eq 0) {
            Write-Ok $file.Name
        } else {
            $failed++
            Write-Warn "$($file.Name) : $($result.Output)"
        }
    }
    Show-ResourceSqlFiles

    if ($failed) { Stop-Kit "$failed fichier(s) en erreur (voir ci-dessus)." }
    Write-Ok "Import terminé : $(Get-DbTableCount $settings) tables dans '$($settings.DbName)'."
}
