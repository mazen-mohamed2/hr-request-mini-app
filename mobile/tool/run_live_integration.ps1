# Opt-in real HTTP integration. Requires Docker, Node/npm and a Flutter SDK.
# From mobile: ./tool/run_live_integration.ps1 -ValidateBackend
# Missing backend dependencies are installed from the repository lockfile.
[CmdletBinding()]
param(
    [string]$FlutterCommand = 'flutter',
    [switch]$ValidateBackend
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backend = Join-Path $workspace 'backend'
$mobile = Join-Path $workspace 'mobile'
if (-not (Get-Command $FlutterCommand -ErrorAction SilentlyContinue)) {
    $localFlutter = Join-Path $workspace '.local/flutter/bin/flutter.bat'
    if ($FlutterCommand -ne 'flutter' -or -not (Test-Path -LiteralPath $localFlutter)) {
        throw 'Flutter not found. Pass -FlutterCommand with an existing Flutter executable.'
    }
    $FlutterCommand = $localFlutter
}
$node = (Get-Command node -ErrorAction Stop).Source
$npm = (Get-Command npm.cmd -ErrorAction Stop).Source
$null = Get-Command docker -ErrorAction Stop

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $Executable $($Arguments -join ' ')" }
}

$environmentNames = @(
    'POSTGRES_USER', 'POSTGRES_PASSWORD', 'POSTGRES_DB', 'DATABASE_URL',
    'TEST_DATABASE_URL', 'NODE_ENV', 'PORT', 'JWT_SECRET', 'LOG_LEVEL',
    'JWT_EXPIRES_IN_SECONDS', 'CORS_ORIGINS',
    'LOGIN_RATE_LIMIT_MAX', 'PUB_CACHE', 'FLUTTER_SUPPRESS_ANALYTICS',
    'DART_SUPPRESS_ANALYTICS', 'CI', 'APPDATA', 'LOCALAPPDATA'
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$initialLocation = Get-Location
$runId = [Guid]::NewGuid().ToString('N')
$scratch = Join-Path $workspace ".local/live-integration-$runId"
$stdout = Join-Path $scratch 'server.stdout.log'
$stderr = Join-Path $scratch 'server.stderr.log'
$containerId = $null
$server = $null
$cleanupFailures = [System.Collections.Generic.List[string]]::new()
function Invoke-CleanupStep {
    param([string]$StepLabel, [ScriptBlock]$Action)
    try { & $Action } catch { $cleanupFailures.Add($StepLabel) }
}

try {
    Invoke-Checked docker @('info', '--format', '{{.ServerVersion}}')
    $null = New-Item -ItemType Directory -Path $scratch
    $env:POSTGRES_USER = 'hr_integration'
    $env:POSTGRES_DB = 'hr_live'
    $env:POSTGRES_PASSWORD = [Guid]::NewGuid().ToString('N')
    $containerId = & docker run --detach --rm --name "hr-live-$runId" `
        --env POSTGRES_USER --env POSTGRES_PASSWORD --env POSTGRES_DB `
        --publish '127.0.0.1::5432' --tmpfs '/var/lib/postgresql/data' `
        postgres:17-alpine
    if ($LASTEXITCODE -ne 0) { throw 'Could not start isolated PostgreSQL.' }
    $containerId = $containerId.Trim()
    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        # Initialization briefly starts a socket-only server. Wait for TCP so
        # that migrations cannot race the temporary server's shutdown.
        & docker exec $containerId pg_isready -h 127.0.0.1 -U $env:POSTGRES_USER -d $env:POSTGRES_DB *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Isolated PostgreSQL did not become ready.' }
    $portBinding = & docker port $containerId '5432/tcp'
    $databasePort = ($portBinding -split ':')[-1].Trim()
    if ($LASTEXITCODE -ne 0 -or $databasePort -notmatch '^\d+$') { throw 'Could not resolve PostgreSQL port.' }
    $databaseBase = "postgresql://$($env:POSTGRES_USER):$($env:POSTGRES_PASSWORD)@127.0.0.1:$databasePort"
    $env:DATABASE_URL = "$databaseBase/hr_live?schema=public"
    $env:TEST_DATABASE_URL = "$databaseBase/hr_live_test?schema=public"
    $env:NODE_ENV = 'development'
    $env:JWT_SECRET = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
    $env:JWT_EXPIRES_IN_SECONDS = '3600'
    $env:CORS_ORIGINS = 'http://localhost:3000'
    $env:LOG_LEVEL = 'silent'
    # A disposable test server needs enough login attempts for independent probes.
    $env:LOGIN_RATE_LIMIT_MAX = '100'
    Set-Location $backend
    if (-not (Test-Path -LiteralPath (Join-Path $backend 'node_modules/.package-lock.json'))) {
        Invoke-Checked $npm @('ci')
    }
    Invoke-Checked $npm @('run', 'prisma:generate')
    # Prisma CLI prints its datasource URL. Capture that output to keep the
    # generated database credential out of console logs, including on failure.
    $migrationOutput = & $npm run prisma:migrate
    if ($LASTEXITCODE -ne 0) { throw 'Integration database migration failed.' }
    $migrationOutput = $null
    Write-Output 'Isolated PostgreSQL migrated.'
    Invoke-Checked $npm @('run', 'prisma:seed')
    if ($ValidateBackend) {
        Invoke-Checked docker @('exec', $containerId, 'psql', '-U', $env:POSTGRES_USER, '-d', 'postgres', '-c', 'CREATE DATABASE hr_live_test')
        Invoke-Checked $npm @('run', 'typecheck')
        Invoke-Checked $npm @('test')
        Invoke-Checked $npm @('run', 'format:check')
    }
    Invoke-Checked $npm @('run', 'build')
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        $env:PORT = [string]$listener.LocalEndpoint.Port
    } finally { $listener.Stop() }
    $server = Start-Process -FilePath $node -ArgumentList 'dist/server.js' `
        -WorkingDirectory $backend -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $apiBaseUrl = "http://127.0.0.1:$($env:PORT)/api"
    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($server.HasExited) { throw 'Express exited before becoming ready.' }
        try {
            $null = Invoke-WebRequest "$apiBaseUrl/me" -UseBasicParsing -TimeoutSec 2
        } catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) {
                $ready = $true
                break
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Express did not become ready.' }
    Write-Output 'Real Express server is ready (protected /api/me returns 401).'
    $env:PUB_CACHE = Join-Path $workspace '.local/pub-cache'
    $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
    $env:DART_SUPPRESS_ANALYTICS = 'true'
    $env:CI = 'true'
    $env:APPDATA = Join-Path $workspace '.local/tool-config'
    $env:LOCALAPPDATA = Join-Path $workspace '.local/tool-cache'
    Set-Location $mobile
    Invoke-Checked $FlutterCommand @(
        'test', 'test_live/backend_integration_test.dart',
        "--dart-define=API_BASE_URL=$apiBaseUrl", '--reporter=expanded'
    )
} finally {
    if ($server) {
        Invoke-CleanupStep 'Express process' {
            if (-not $server.HasExited) {
                try { Stop-Process -Id $server.Id -Force } catch {
                    # Exiting between HasExited and Stop-Process is harmless.
                    $server.Refresh()
                    if (-not $server.HasExited) { throw }
                }
            }
        }
        Invoke-CleanupStep 'Express process handle' { $server.Dispose() }
    }
    if ($containerId) {
        Invoke-CleanupStep 'PostgreSQL container' {
            & docker rm --force $containerId | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Container removal failed.' }
        }
    }
    foreach ($path in @($stdout, $stderr)) {
        Invoke-CleanupStep 'temporary server log' {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }
    # No recursive removal: only the two known logs and their now-empty folder.
    Invoke-CleanupStep 'temporary directory' {
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch }
    }
    Invoke-CleanupStep 'working directory restoration' { Set-Location $initialLocation }
    foreach ($name in $environmentNames) {
        Invoke-CleanupStep "environment restoration ($name)" {
            [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
        }
    }
    if ($cleanupFailures.Count) {
        throw "Integration cleanup failed: $($cleanupFailures -join ', '). Check resources for run $runId."
    }
}
