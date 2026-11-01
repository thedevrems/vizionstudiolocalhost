# Arrête la base de données (XAMPP ou Docker). Les données sont conservées.
. "$PSScriptRoot\lib.ps1"

Invoke-Main {
    $settings = Get-KitSettings
    switch ($settings.DbMode) {
        'docker' {
            & docker compose -f $ComposeFile stop
            if ($LASTEXITCODE -ne 0) { Stop-Kit "Impossible d'arrêter les conteneurs Docker (Docker Desktop est-il lancé ?)." }
            Write-Ok 'MariaDB (Docker) arrêté. Tes données sont conservées.'
        }
        'xampp' {
            if (-not (Test-Port $settings.DbPort)) { Write-Ok 'MySQL (XAMPP) est déjà arrêté.'; return }
            $env:MYSQL_PWD = $settings.DbPassword
            $admin = Join-Path $settings.XamppPath 'mysql\bin\mysqladmin.exe'
            $result = Invoke-Native $admin @('-h', '127.0.0.1', '-P', "$($settings.DbPort)", '-u', $settings.DbUser, 'shutdown')
            if ($result.Code -ne 0) { Stop-Kit "Arrêt impossible : $($result.Output)" }
            Write-Ok 'MySQL (XAMPP) arrêté.'
        }
        default { Stop-Kit 'Aucune base de données configurée (DB_MODE) : lance 1-INSTALLER.bat.' }
    }
}
