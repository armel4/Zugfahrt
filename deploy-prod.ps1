# =================================================================
# PRODUCTION DEPLOYMENT SCRIPT - ZUGFAHRT APP (PowerShell)
# Automated deployment with security checks and rollback for Windows
# =================================================================

param(
    [Parameter(Position = 0)]
    [ValidateSet("deploy", "rollback", "status", "logs", "backup")]
    [string]$Action = "deploy",
    
    [Parameter(Position = 1)]
    [string]$Service = ""
)

# Configuration
$ProjectName = "zugfahrt-prod"
$BackupDir = ".\backups"
$ComposeFile = "docker-compose.prod.yml"
$EnvFile = ".env"

# Functions
function Write-Info {
    param($Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param($Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param($Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param($Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Pre-deployment checks
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check if Docker is running
    try {
        docker info | Out-Null
    }
    catch {
        Write-Error "Docker is not running or not accessible"
        exit 1
    }
    
    # Check if Docker Compose is available
    if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
        Write-Error "Docker Compose is not installed"
        exit 1
    }
    
    # Check if environment file exists
    if (-not (Test-Path $EnvFile)) {
        Write-Error "Environment file $EnvFile not found. Copy from .env.example and configure."
        exit 1
    }
    
    # Check if compose file exists
    if (-not (Test-Path $ComposeFile)) {
        Write-Error "Docker Compose file $ComposeFile not found"
        exit 1
    }
    
    Write-Success "Prerequisites check passed"
}

# Backup database
function Backup-Database {
    Write-Info "Creating database backup..."
    
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    
    $BackupFile = "$BackupDir\backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
    
    # Only backup if database is running
    $DbStatus = docker-compose -f $ComposeFile ps db
    if ($DbStatus -match "Up") {
        docker-compose -f $ComposeFile exec -T db pg_dump -U zugfahrt_user zugfahrt_prod | Out-File -FilePath $BackupFile -Encoding UTF8
        Write-Success "Database backup created: $BackupFile"
    }
    else {
        Write-Warning "Database not running, skipping backup"
    }
}

# Build application
function Build-Application {
    Write-Info "Building application..."
    
    # Build with production dockerfile
    docker-compose -f $ComposeFile build --no-cache app
    
    Write-Success "Application build completed"
}

# Deploy services
function Deploy-Services {
    Write-Info "Deploying services..."
    
    # Stop existing services gracefully
    docker-compose -f $ComposeFile down --timeout 30
    
    # Start services in correct order
    docker-compose -f $ComposeFile up -d db redis
    
    # Wait for database to be ready
    Write-Info "Waiting for database to be ready..."
    $timeout = 60
    $elapsed = 0
    do {
        Start-Sleep 2
        $elapsed += 2
        $ready = docker-compose -f $ComposeFile exec db pg_isready -U zugfahrt_user
    } while ($ready -notmatch "accepting connections" -and $elapsed -lt $timeout)
    
    if ($elapsed -ge $timeout) {
        Write-Error "Database failed to start within timeout"
        throw "Database startup timeout"
    }
    
    # Start application
    docker-compose -f $ComposeFile up -d app
    
    # Start reverse proxy and monitoring
    docker-compose -f $ComposeFile up -d nginx prometheus grafana
    
    Write-Success "Services deployed successfully"
}

# Health check
function Test-Health {
    Write-Info "Performing health checks..."
    
    # Wait for application to be ready
    Write-Info "Waiting for application to be healthy..."
    $timeout = 120
    $elapsed = 0
    do {
        Start-Sleep 5
        $elapsed += 5
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -UseBasicParsing -TimeoutSec 10
            $healthy = $response.StatusCode -eq 200
        }
        catch {
            $healthy = $false
        }
    } while (-not $healthy -and $elapsed -lt $timeout)
    
    if ($elapsed -ge $timeout) {
        Write-Error "Application health check failed"
        return $false
    }
    
    # Check database connection
    $dbCheck = docker-compose -f $ComposeFile exec -T db pg_isready -U zugfahrt_user
    if ($dbCheck -match "accepting connections") {
        Write-Success "Database health check passed"
    }
    else {
        Write-Error "Database health check failed"
        return $false
    }
    
    # Check Redis connection
    $redisCheck = docker-compose -f $ComposeFile exec -T redis redis-cli ping
    if ($redisCheck -match "PONG") {
        Write-Success "Redis health check passed"
    }
    else {
        Write-Error "Redis health check failed"
        return $false
    }
    
    # Check Nginx
    try {
        $nginxResponse = Invoke-WebRequest -Uri "http://localhost/health" -UseBasicParsing -TimeoutSec 10
        if ($nginxResponse.StatusCode -eq 200) {
            Write-Success "Nginx health check passed"
        }
        else {
            Write-Error "Nginx health check failed"
            return $false
        }
    }
    catch {
        Write-Error "Nginx health check failed"
        return $false
    }
    
    Write-Success "All health checks passed"
    return $true
}

# Rollback function
function Invoke-Rollback {
    Write-Warning "Rolling back deployment..."
    
    # Stop current deployment
    docker-compose -f $ComposeFile down --timeout 30
    
    # Restore from backup if available
    $LatestBackup = Get-ChildItem "$BackupDir\backup_*.sql" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($LatestBackup) {
        Write-Info "Restoring from backup: $($LatestBackup.FullName)"
        docker-compose -f $ComposeFile up -d db
        Start-Sleep 10
        Get-Content $LatestBackup.FullName | docker-compose -f $ComposeFile exec -T db psql -U zugfahrt_user zugfahrt_prod
    }
    
    Write-Error "Rollback completed"
}

# Cleanup old images
function Invoke-Cleanup {
    Write-Info "Cleaning up old Docker images..."
    
    docker image prune -f
    docker volume prune -f
    
    # Keep only last 5 backups
    if (Test-Path $BackupDir) {
        $OldBackups = Get-ChildItem "$BackupDir\backup_*.sql" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 5
        $OldBackups | Remove-Item -Force
    }
    
    Write-Success "Cleanup completed"
}

# Show deployment status
function Show-Status {
    Write-Info "Deployment status:"
    docker-compose -f $ComposeFile ps
    
    Write-Host ""
    Write-Info "Application URLs:"
    Write-Host "  • Application: http://localhost (or your domain)"
    Write-Host "  • Health Check: http://localhost/health"
    Write-Host "  • Prometheus: http://localhost:9090"
    Write-Host "  • Grafana: http://localhost:3000 (admin/password from .env)"
    Write-Host ""
    
    Write-Info "Logs:"
    Write-Host "  • Application: docker-compose -f $ComposeFile logs -f app"
    Write-Host "  • All services: docker-compose -f $ComposeFile logs -f"
}

# Main deployment function
function Invoke-Deploy {
    Write-Info "Starting production deployment for Zugfahrt App..."
    
    try {
        Test-Prerequisites
        Backup-Database
        Build-Application
        Deploy-Services
        
        if (Test-Health) {
            Invoke-Cleanup
            Show-Status
            Write-Success "🎉 Production deployment completed successfully!"
        }
        else {
            Write-Error "Health checks failed, initiating rollback..."
            Invoke-Rollback
            exit 1
        }
    }
    catch {
        Write-Error "Deployment failed: $($_.Exception.Message)"
        Write-Warning "Initiating rollback..."
        Invoke-Rollback
        exit 1
    }
}

# Main script logic
switch ($Action) {
    "deploy" {
        Invoke-Deploy
    }
    "rollback" {
        Invoke-Rollback
    }
    "status" {
        Show-Status
    }
    "logs" {
        if ($Service) {
            docker-compose -f $ComposeFile logs -f $Service
        }
        else {
            docker-compose -f $ComposeFile logs -f
        }
    }
    "backup" {
        Backup-Database
    }
    default {
        Write-Host "Usage: .\deploy-prod.ps1 {deploy|rollback|status|logs [service]|backup}"
        exit 1
    }
}