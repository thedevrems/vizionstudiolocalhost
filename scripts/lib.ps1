# =============================================================
#  Fonctions communes du kit localhost FiveM
#  Chargé par les autres scripts : . "$PSScriptRoot\lib.ps1"
# =============================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root          = Split-Path -Parent $PSScriptRoot
$ConfigPath    = Join-Path $Root 'config.ini'
$ArtifactsDir  = Join-Path $Root 'artifacts'
$ServerDataDir = Join-Path $Root 'server-data'
$SqlDir        = Join-Path $Root 'sql'
$ComposeFile   = Join-Path $Root 'docker-compose.yml'
$KitCfgName    = 'kit-localhost.cfg'
$DbContainer   = 'fivem-localhost-db'
$ArtifactsApi  = 'https://changelogs-live.fivem.net/api/changelog/versions/win32/server'
$Utf8NoBom     = New-Object System.Text.UTF8Encoding($false)

$LicensePattern    = '(?im)^([ \t]*(?:set[ \t]+)?sv_licenseKey[ \t]+)(?:"([^"\r\n]*)"|([^\s"]*))[^\r\n]*'
$ConnectionPattern = '(?im)^([ \t]*(?:set|setr)[ \t]+mysql_connection_string[ \t]+)(?:"([^"\r\n]*)"|([^\s"]*))[^\r\n]*'

# ---------- Affichage ----------

function Write-Title([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 64) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 64) -ForegroundColor DarkCyan
}
function Write-Step([string]$Text) { Write-Host "`n> $Text" -ForegroundColor White }
function Write-Ok([string]$Text)   { Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "  $Text" -ForegroundColor Gray }
function Write-Warn([string]$Text) { Write-Host "  [!] $Text" -ForegroundColor Yellow }

# Arrête le script avec un message clair pour l'utilisateur
function Stop-Kit([string]$Text) { throw [System.OperationCanceledException]::new($Text) }

function Invoke-Main([scriptblock]$Body) {
    try {
        & $Body
        exit 0
    } catch {
        Write-Host ''
        Write-Host "  [ERREUR] $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception -isnot [System.OperationCanceledException]) {
            Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray
        }
        exit 1
    }
}

function Test-Yes([string]$Value) { $Value -match '^(1|true|yes|y|oui|o)$' }

function Show-PathWarnings {
    if ($Root -match '\\OneDrive') {
        Write-Warn 'Le kit est dans OneDrive : la synchro peut bloquer des fichiers du serveur. Conseil : C:\FiveM\localhost'
    }
    if ($Root -match '[^\x00-\x7F]| ') {
        Write-Warn 'Le chemin du kit contient des accents ou des espaces : certaines ressources peuvent planter. Conseil : C:\FiveM\localhost'
    }
}

# ---------- Fichiers ----------

function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $Utf8NoBom) }

# Lance une commande externe sans rien afficher et renvoie son code + sa sortie
function Invoke-Native([string]$File, [string[]]$Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $File @Arguments 2>&1 | ForEach-Object { "$_" }
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = (@($output | Where-Object { $_ }) -join "`n").Trim() }
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Test-Port([int]$Port) {
    $client = New-Object Net.Sockets.TcpClient
    try { $client.ConnectAsync('127.0.0.1', $Port).Wait(700) } catch { $false } finally { $client.Close() }
}

function Wait-Until([scriptblock]$Condition, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (& $Condition) { return $true }
        Start-Sleep -Seconds 2
    }
    $false
}

# ---------- config.ini ----------

function Read-Config {
    if (-not (Test-Path $ConfigPath)) { Copy-Item (Join-Path $Root 'config.example.ini') $ConfigPath }
    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($ConfigPath)) {
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*=(.*)$') { $values[$Matches[1]] = $Matches[2].Trim().Trim('"') }
    }
    $values
}

function Set-ConfigValue([string]$Key, [string]$Value) {
    $text = Read-Text $ConfigPath
    $pattern = "(?m)^[ \t]*$Key[ \t]*=[^\r\n]*"
    $line = "$Key=$Value"
    if ([regex]::IsMatch($text, $pattern)) {
        $text = [regex]::Replace($text, $pattern, $line.Replace('$', '$$'))
    } else {
        $text = $text.TrimEnd() + "`r`n$line`r`n"
    }
    Write-Text $ConfigPath $text
}

function Get-KitSettings {
    $c = Read-Config
    $get = { param($Key, $Default) if ($c[$Key]) { $c[$Key] } else { $Default } }
    $mode = "$($c['DB_MODE'])".ToLower()
    # Mot de passe vide = valeur par défaut du mode choisi
    $password = & $get 'DB_PASSWORD' $(if ($mode -eq 'docker') { 'fivem' } else { '' })

    [pscustomobject]@{
        LicenseKey      = $c['LICENSE_KEY']
        ServerCfg       = & $get 'SERVER_CFG' 'server.cfg'
        ArtifactChannel = (& $get 'ARTIFACT_CHANNEL' 'recommended').ToLower()
        ArtifactUrl     = $c['ARTIFACT_URL']
        DbMode          = $mode
        DbName          = $c['DB_NAME']
        DbUser          = & $get 'DB_USER' 'root'
        DbPassword      = $password
        DbPort          = [int](& $get 'DB_PORT' '3306')
        XamppPath       = & $get 'XAMPP_PATH' 'C:\xampp'
        PmaPort         = [int](& $get 'PMA_PORT' '8080')
        SyncServerCfg   = Test-Yes (& $get 'SYNC_SERVER_CFG' 'true')
        ClearCache      = Test-Yes (& $get 'CLEAR_CACHE_ON_START' 'false')
    }
}

function Test-LicenseKey([string]$Key) {
    [bool]$Key -and $Key -notmatch '(?i)change|your|votre|ta_cle|^x+$|^key$|licen[cs]e'
}

# ---------- FXServer (artifacts) ----------

function Get-FxServerPath { Join-Path $ArtifactsDir 'FXServer.exe' }

function Get-InstalledBuild {
    $file = Join-Path $ArtifactsDir 'build.txt'
    if (Test-Path $file) { (Read-Text $file).Trim() }
}

function Install-Artifacts($Settings) {
    if ($Settings.ArtifactUrl) {
        $url = $Settings.ArtifactUrl
        $build = if ($url -match '/(\d+)-[0-9a-f]+/') { $Matches[1] } else { 'custom' }
    } else {
        $channel = $Settings.ArtifactChannel
        if ($channel -notin 'recommended', 'latest', 'optional', 'critical') {
            Stop-Kit "ARTIFACT_CHANNEL invalide : '$channel' (valeurs possibles : recommended, latest, optional)."
        }
        Write-Info "Recherche de la version '$channel' de FXServer..."
        $versions = Invoke-RestMethod -Uri $ArtifactsApi -UseBasicParsing
        $build = $versions.$channel
        $url = $versions."$($channel)_download"
    }

    if ((Get-InstalledBuild) -eq $build -and (Test-Path (Get-FxServerPath))) {
        Write-Ok "FXServer build $build déjà installé."
        return
    }
    if (Get-Process FXServer -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$ArtifactsDir*" }) {
        Stop-Kit 'Le serveur FiveM tourne encore : ferme-le avant de mettre à jour FXServer.'
    }

    Write-Info "Téléchargement de FXServer build $build..."
    $zip = Join-Path $env:TEMP "fxserver-$build.zip"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L --fail --progress-bar -o $zip $url
        if ($LASTEXITCODE -ne 0) { Stop-Kit "Échec du téléchargement : $url" }
    } else {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    }

    # Extraction dans un dossier temporaire, puis remplacement de l'ancienne version
    Write-Info 'Extraction...'
    $staging = "$ArtifactsDir.new"
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
    New-Item -ItemType Directory $staging | Out-Null
    if (Get-Command tar.exe -ErrorAction SilentlyContinue) { & tar.exe -xf $zip -C $staging }
    if (-not (Test-Path (Join-Path $staging 'FXServer.exe'))) { Expand-Archive -Path $zip -DestinationPath $staging -Force }
    if (-not (Test-Path (Join-Path $staging 'FXServer.exe'))) { Stop-Kit "L'archive téléchargée ne contient pas FXServer.exe." }

    if (Test-Path $ArtifactsDir) { Remove-Item $ArtifactsDir -Recurse -Force }
    Rename-Item $staging (Split-Path $ArtifactsDir -Leaf)
    Write-Text (Join-Path $ArtifactsDir 'build.txt') $build
    Remove-Item $zip -Force
    Write-Ok "FXServer build $build installé dans artifacts\"
}

# ---------- server.cfg ----------

function Find-ServerCfg($Settings) {
    $path = Join-Path $ServerDataDir $Settings.ServerCfg
    if (Test-Path $path) { return $path }

    $nested = Get-ChildItem $ServerDataDir -Filter $Settings.ServerCfg -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($nested) {
        $folder = $nested.DirectoryName.Substring($Root.Length + 1)
        Stop-Kit "Ton $($Settings.ServerCfg) est dans un sous-dossier ($folder).`n  Déplace tout le contenu de ce dossier directement dans server-data\ (README, étape 4)."
    }
    Stop-Kit "Aucun $($Settings.ServerCfg) dans server-data\ : copie ta base dedans (README, étape 4).`n  Ta base n'a pas de server.cfg ? Copie templates\server.cfg dans server-data\."
}

# server.cfg + les fichiers qu'il charge avec "exec" (permissions.cfg, resources.cfg...)
function Get-CfgFiles([string]$MainCfg) {
    $seen  = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files = [Collections.Generic.List[string]]::new()
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue((Resolve-Path $MainCfg).Path)
    while ($queue.Count) {
        $file = $queue.Dequeue()
        if (-not $seen.Add($file)) { continue }
        $files.Add($file)
        foreach ($m in [regex]::Matches((Read-Text $file), '(?im)^[ \t]*exec[ \t]+"?([^"\s@][^"\s]*)')) {
            $child = Join-Path $ServerDataDir $m.Groups[1].Value
            if (Test-Path $child -PathType Leaf) { $queue.Enqueue((Resolve-Path $child).Path) }
        }
    }
    $files
}

function Find-CfgSetting([string[]]$Files, [string]$Pattern) {
    foreach ($file in $Files) {
        $m = [regex]::Match((Read-Text $file), $Pattern)
        if ($m.Success) {
            $value = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value }
            return [pscustomobject]@{ File = $file; Value = $value }
        }
    }
}

function Get-CfgConnection($Settings) {
    $cfg = Join-Path $ServerDataDir $Settings.ServerCfg
    if (Test-Path $cfg) { Find-CfgSetting @(Get-CfgFiles $cfg) $ConnectionPattern }
}

# Renvoie la ligne à ajouter au lancement si le réglage n'existe dans aucun .cfg,
# sinon met à jour la ligne existante (une sauvegarde .bak est faite la première fois)
function Use-CfgValue($Settings, $Existing, [string]$Pattern, [string]$Line, [string]$Value) {
    if (-not $Existing) { return "$Line `"$Value`"" }
    if ($Existing.Value -eq $Value) { return }

    $fileName = Split-Path $Existing.File -Leaf
    if (-not $Settings.SyncServerCfg) {
        Write-Warn "SYNC_SERVER_CFG=false : la valeur de $fileName est conservée pour '$Line'."
        return
    }
    $backup = "$($Existing.File).bak"
    if (-not (Test-Path $backup)) { Copy-Item $Existing.File $backup }
    Write-Text $Existing.File ([regex]::Replace((Read-Text $Existing.File), $Pattern, '${1}"' + $Value.Replace('$', '$$') + '"'))
    Write-Ok "'$Line' mis à jour dans $fileName (sauvegarde : $fileName.bak)"
}

function Get-GamePort([string[]]$CfgFiles) {
    foreach ($file in $CfgFiles) {
        $m = [regex]::Match((Read-Text $file), '(?im)^[ \t]*endpoint_add_tcp[ \t]+"?[^"\r\n]*:(\d+)')
        if ($m.Success) { return [int]$m.Groups[1].Value }
    }
    30120
}

function Test-UsesDatabase([string[]]$CfgFiles) {
    if (Find-CfgSetting $CfgFiles $ConnectionPattern) { return $true }
    [bool](Get-ChildItem (Join-Path $ServerDataDir 'resources') -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in 'oxmysql', 'mysql-async', 'ghmattimysql' } | Select-Object -First 1)
}

# ---------- Base de données ----------

function Get-DbNameFromConnection([string]$Connection) {
    if ($Connection -match '^mysql://[^/]*/([^?/]+)') { return [uri]::UnescapeDataString($Matches[1]) }
    if ($Connection -match '(?i)(?:^|;)\s*(?:database|db)\s*=\s*([^;]+)') { return $Matches[1].Trim() }
}

# Nom de la base : DB_NAME (config.ini) > nom indiqué dans server.cfg > "fivem"
function Complete-DbName($Settings, $Connection) {
    if (-not $Settings.DbName) {
        $fromCfg = if ($Connection) { Get-DbNameFromConnection $Connection.Value }
        $Settings.DbName = if ($fromCfg) { $fromCfg } else { 'fivem' }
    }
    if ($Settings.DbName -notmatch '^[A-Za-z0-9_-]+$') {
        Stop-Kit "DB_NAME invalide : '$($Settings.DbName)' (lettres, chiffres, _ et - uniquement)."
    }
}

function New-ConnectionString($Settings, [string]$Current) {
    # 127.0.0.1 et pas "localhost" : évite l'erreur oxmysql ECONNREFUSED ::1:3306
    $uriSafe = ($Settings.DbUser + $Settings.DbPassword) -match '^[A-Za-z0-9._~-]*$'
    if (-not $uriSafe -or ($Current -and $Current -notmatch '^mysql://')) {
        return 'server=127.0.0.1;port={0};database={1};userid={2};password={3}' -f $Settings.DbPort, $Settings.DbName, $Settings.DbUser, $Settings.DbPassword
    }
    $auth = $Settings.DbUser
    if ($Settings.DbPassword) { $auth += ":$($Settings.DbPassword)" }
    $query = if ($Current -match '\?(.+)$') { $Matches[1] } else { 'charset=utf8mb4' }
    'mysql://{0}@127.0.0.1:{1}/{2}?{3}' -f $auth, $Settings.DbPort, $Settings.DbName, $query
}

function Start-Database($Settings) {
    switch ($Settings.DbMode) {
        'xampp'  { Start-XamppDatabase $Settings }
        'docker' { Start-DockerDatabase $Settings }
        default  { Stop-Kit 'Aucune base de données choisie : lance 1-INSTALLER.bat (ou mets DB_MODE=xampp / docker dans config.ini).' }
    }
}

function Start-XamppDatabase($Settings) {
    if (Test-Port $Settings.DbPort) { Write-Ok "MySQL répond sur le port $($Settings.DbPort)."; return }

    $mysqld = Join-Path $Settings.XamppPath 'mysql\bin\mysqld.exe'
    if (-not (Test-Path $mysqld)) {
        Stop-Kit "XAMPP introuvable dans '$($Settings.XamppPath)'. Installe XAMPP (README, étape 2A) ou corrige XAMPP_PATH dans config.ini."
    }
    Write-Info 'Démarrage de MySQL (XAMPP)...'
    $ini = Join-Path $Settings.XamppPath 'mysql\bin\my.ini'
    $process = Start-Process -FilePath $mysqld -ArgumentList "--defaults-file=`"$ini`"", '--standalone' `
        -WorkingDirectory $Settings.XamppPath -WindowStyle Hidden -PassThru
    $null = Wait-Until { $process.HasExited -or (Test-Port $Settings.DbPort) } 30
    # Avec des données corrompues, MySQL ouvre le port puis plante quelques secondes plus tard
    Start-Sleep -Seconds 4
    if ($process.HasExited -or -not (Test-Port $Settings.DbPort)) {
        $log = Join-Path $Settings.XamppPath 'mysql\data\mysql_error.log'
        Stop-Kit "MySQL (XAMPP) s'arrête au démarrage. Journal : $log`n  Voir README, Dépannage : « XAMPP : MySQL ne démarre pas »."
    }
    Write-Ok "MySQL (XAMPP) démarré sur le port $($Settings.DbPort)."
}

function Test-DockerEngine { (Invoke-Native 'docker' @('info', '--format', '{{.ServerVersion}}')).Code -eq 0 }

function Get-DbContainerState([string]$Format) { (Invoke-Native 'docker' @('inspect', '-f', $Format, $DbContainer)).Output }

function Start-DockerDatabase($Settings) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Stop-Kit "Docker n'est pas installé. Installe Docker Desktop (README, étape 2B) ou mets DB_MODE=xampp dans config.ini."
    }
    if (-not (Test-DockerEngine)) {
        $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (-not (Test-Path $desktop)) { Stop-Kit 'Docker ne répond pas : lance Docker Desktop puis réessaie.' }
        Write-Info 'Démarrage de Docker Desktop (jusqu''à 2 minutes)...'
        Start-Process $desktop
        if (-not (Wait-Until { Test-DockerEngine } 180)) {
            Stop-Kit 'Docker Desktop ne répond pas. Ouvre-le, attends "Engine running" puis réessaie.'
        }
    }
    if ((Get-DbContainerState '{{.State.Running}}') -ne 'true' -and (Test-Port $Settings.DbPort)) {
        Stop-Kit "Le port $($Settings.DbPort) est déjà pris (MySQL de XAMPP ou un autre MySQL ?). Arrête-le ou change DB_PORT dans config.ini."
    }

    Write-Info 'Démarrage de MariaDB (Docker)... Le premier lancement télécharge les images.'
    $env:DB_NAME     = $Settings.DbName
    $env:DB_PASSWORD = $Settings.DbPassword
    $env:DB_PORT     = $Settings.DbPort
    $env:PMA_PORT    = $Settings.PmaPort
    & docker compose -f $ComposeFile up -d
    if ($LASTEXITCODE -ne 0) { Stop-Kit 'docker compose a échoué (voir le message ci-dessus).' }
    if (-not (Wait-Until { (Get-DbContainerState '{{.State.Health.Status}}') -eq 'healthy' } 120)) {
        Stop-Kit "MariaDB ne démarre pas. Regarde les logs : docker logs $DbContainer"
    }
    Write-Ok "MariaDB (Docker) prêt sur le port $($Settings.DbPort) - phpMyAdmin : http://localhost:$($Settings.PmaPort)"
}

# Le mot de passe passe par la variable MYSQL_PWD : jamais en clair dans la ligne de commande
function Get-DbClient($Settings, [switch]$Stdin) {
    $env:MYSQL_PWD = $Settings.DbPassword
    if ($Settings.DbMode -eq 'docker') {
        $docker = (Get-Command docker).Source
        $exec = @('exec')
        if ($Stdin) { $exec += '-i' }
        return @{ File = $docker; Args = $exec + @('-e', 'MYSQL_PWD', $DbContainer, 'mariadb', '-u', $Settings.DbUser) }
    }
    $mysql = Join-Path $Settings.XamppPath 'mysql\bin\mysql.exe'
    if (-not (Test-Path $mysql)) { Stop-Kit "mysql.exe introuvable dans '$($Settings.XamppPath)'. Vérifie XAMPP_PATH dans config.ini." }
    @{ File = $mysql; Args = @('-h', '127.0.0.1', '-P', "$($Settings.DbPort)", '-u', $Settings.DbUser) }
}

function Invoke-DbQuery($Settings, [string]$Query) {
    $client = Get-DbClient $Settings
    Invoke-Native $client.File ($client.Args + @('--batch', '--skip-column-names', '-e', $Query))
}

# Vérifie la connexion et crée la base si elle n'existe pas
function Initialize-Database($Settings) {
    $test = Invoke-DbQuery $Settings 'SELECT 1'
    if ($test.Code -ne 0) {
        Stop-Kit "Connexion à la base impossible : $($test.Output)`n  Vérifie DB_USER / DB_PASSWORD / DB_PORT dans config.ini."
    }
    $create = Invoke-DbQuery $Settings ('CREATE DATABASE IF NOT EXISTS `{0}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci' -f $Settings.DbName)
    if ($create.Code -ne 0) { Stop-Kit "Impossible de créer la base '$($Settings.DbName)' : $($create.Output)" }
}

function Get-DbTableCount($Settings) {
    $result = Invoke-DbQuery $Settings ("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '{0}'" -f $Settings.DbName)
    [int]$result.Output
}

function Import-SqlFile($Settings, [string]$Path) {
    $client = Get-DbClient $Settings -Stdin
    $arguments = $client.Args + @('--default-character-set=utf8mb4', $Settings.DbName)
    $errFile = [IO.Path]::GetTempFileName()
    $outFile = [IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $client.File -ArgumentList $arguments -NoNewWindow -Wait -PassThru `
            -RedirectStandardInput $Path -RedirectStandardError $errFile -RedirectStandardOutput $outFile
        [pscustomobject]@{ Code = $process.ExitCode; Output = (Read-Text $errFile).Trim() }
    } finally {
        Remove-Item $errFile, $outFile -ErrorAction SilentlyContinue
    }
}
