# ZUGFAHRT PRO - PRODUCTION SECURITY HARDENING VALIDATION SCRIPT
# ================================================================
# This script validates that all security measures are properly implemented
# and no sensitive information is exposed before production deployment.
# 
# Author: Security Engineering Team
# Date: November 28, 2025
# Version: 2.1 Enterprise

param(
    [switch]$Verbose,
    [string]$ProjectPath = "."
)

Write-Host "ZUGFART PRO - PRODUCTION SECURITY HARDENING" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$ErrorCount = 0
$WarningCount = 0

# Colors for output
$Green = "Green"
$Red = "Red"
$Yellow = "Yellow"
$Cyan = "Cyan"

function Write-Status($Message, $Type = "INFO") {
    switch ($Type) {
        "PASS" { Write-Host "✅ $Message" -ForegroundColor $Green }
        "FAIL" { Write-Host "❌ $Message" -ForegroundColor $Red; $script:ErrorCount++ }
        "WARN" { Write-Host "⚠️  $Message" -ForegroundColor $Yellow; $script:WarningCount++ }
        "INFO" { Write-Host "ℹ️  $Message" -ForegroundColor $Cyan }
    }
}

# 1. Check for exposed secrets
Write-Host "Checking for exposed secrets..."
$SecretsFound = $false

# Check for hardcoded API keys
$ApiKeyPattern = "(sk-[a-zA-Z0-9-_]{20,}|[a-zA-Z0-9]{32,})"
$ExcludePatterns = @("\.env", "\.git", "target", "logs", "node_modules")

Get-ChildItem -Recurse -File | Where-Object {
    $exclude = $false
    foreach ($pattern in $ExcludePatterns) {
        if ($_.FullName -like "*$pattern*") {
            $exclude = $true
            break
        }
    }
    !$exclude -and ($_.Extension -in @(".java", ".properties", ".yml", ".yaml", ".md", ".json", ".js", ".jsx"))
} | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -and $content -match $ApiKeyPattern) {
        # Exclude environment variable references
        if ($content -notmatch '\$\{[^}]+\}' -or $content -match 'sk-[a-zA-Z0-9-_]{40,}') {
            Write-Status "CRITICAL: Exposed secret found in $($_.Name)" "FAIL"
            if ($Verbose) {
                $content | Select-String $ApiKeyPattern | ForEach-Object {
                    Write-Host "   Line $($_.LineNumber): $($_.Line.Substring(0, [Math]::Min(50, $_.Line.Length)))..." -ForegroundColor Red
                }
            }
            $SecretsFound = $true
        }
    }
}

if (!$SecretsFound) {
    Write-Status "No hardcoded secrets found" "PASS"
}

# 2. Check production configuration
Write-Host "`nChecking production configuration..."

# Check application-prod.properties
$ProdConfig = "src/main/resources/application-prod.properties"
if (Test-Path $ProdConfig) {
    $content = Get-Content $ProdConfig -Raw
    
    # Check for environment variables
    if ($content -match '\$\{[^}]+\}') {
        Write-Status "Production config uses environment variables" "PASS"
    }
    else {
        Write-Status "Production config should use environment variables" "WARN"
    }
    
    # Check for validate DDL
    if ($content -match "spring\.jpa\.hibernate\.ddl-auto=validate") {
        Write-Status "Database schema validation enabled (production safe)" "PASS"
    }
    else {
        Write-Status "Consider using ddl-auto=validate for production" "WARN"
    }
}
else {
    Write-Status "Production configuration file not found" "WARN"
}

# 3. Check for debug code
Write-Host "`nChecking for debug code..."
$DebugFound = $false

Get-ChildItem -Recurse -File -Include "*.java" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($content) {
        # Check for debug statements
        if ($content -match "(System\.out\.println|printStackTrace|\.debug\(|TODO|FIXME)") {
            $matches = $content | Select-String "(System\.out\.println|printStackTrace|\.debug\(|TODO|FIXME)" -AllMatches
            foreach ($match in $matches.Matches) {
                if ($match.Value -notmatch "logger\.debug" -and $match.Value -notmatch "log\.debug") {
                    Write-Status "Debug code found in $($_.Name): $($match.Value)" "WARN"
                    $DebugFound = $true
                }
            }
        }
    }
}

if (!$DebugFound) {
    Write-Status "No critical debug code found" "PASS"
}

# 4. Check SecurityConfig
Write-Host "`nChecking security configuration..."
$SecurityConfig = "src/main/java/com/karibu/tech/config/SecurityConfig.java"
if (Test-Path $SecurityConfig) {
    $content = Get-Content $SecurityConfig -Raw
    
    if ($content -match "BCryptPasswordEncoder") {
        Write-Status "BCrypt password encoder configured" "PASS"
    }
    else {
        Write-Status "BCrypt password encoder not found" "FAIL"
    }
    
    if ($content -match "sessionManagement.*SessionCreationPolicy\.STATELESS") {
        Write-Status "Stateless session management configured" "PASS"
    }
    else {
        Write-Status "Stateless session management recommended" "WARN"
    }
}
else {
    Write-Status "SecurityConfig.java not found" "FAIL"
}

# 5. Generate production secrets template
Write-Host "`nGenerating production secrets template..."
$EnvTemplate = @"
# ZUGFAHRT PRO - PRODUCTION ENVIRONMENT VARIABLES
# ===============================================
# SECURITY: Replace ALL placeholder values with real secrets
# NEVER commit this file with real values

# Database Configuration
DB_URL=jdbc:postgresql://your-db-host:5432/your-db-name
DB_USERNAME=your_db_username
DB_PASSWORD=YOUR_STRONG_DB_PASSWORD

# JWT Configuration (CRITICAL)
JWT_SECRET=YOUR_256BIT_CRYPTOGRAPHICALLY_RANDOM_SECRET_HERE
JWT_EXPIRATION=1800000

# CORS Configuration
CORS_ALLOWED_ORIGINS=https://your-frontend.netlify.app
FRONTEND_URL=https://your-frontend.netlify.app

# OpenAI Configuration
OPENAI_API_KEY=sk-proj-your_actual_openai_key_here
OPENAI_MODEL=gpt-4o-2024-11-20

# Email Configuration
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=your-email@gmail.com
MAIL_PASSWORD=your_gmail_app_password
MAIL_FROM=your-email@gmail.com
APP_NAME=Zugfahrt Pro

# Security Settings
CSRF_ENABLED=true
SSL_ENABLED=false

# Server Configuration
PORT=8080
SPRING_PROFILES_ACTIVE=prod
"@

$EnvTemplate | Out-File -FilePath ".env.production.template" -Encoding UTF8
Write-Status "Production secrets template created: .env.production.template" "PASS"

# 6. Final summary
Write-Host "`n" + "="*50
Write-Host "SECURITY VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "="*50

if ($ErrorCount -eq 0 -and $WarningCount -eq 0) {
    Write-Host "🎉 SECURITY HARDENING COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "   All automated checks passed" -ForegroundColor Green
    Write-Host "   Your application is ready for production deployment" -ForegroundColor Green
}
elseif ($ErrorCount -eq 0) {
    Write-Host "✅ SECURITY HARDENING MOSTLY COMPLETED" -ForegroundColor Yellow
    Write-Host "   $WarningCount warnings found - review recommended" -ForegroundColor Yellow
    Write-Host "   Application can be deployed but review warnings first" -ForegroundColor Yellow
}
else {
    Write-Host "❌ SECURITY HARDENING INCOMPLETE" -ForegroundColor Red
    Write-Host "   $ErrorCount critical errors must be fixed" -ForegroundColor Red
    Write-Host "   $WarningCount warnings should be reviewed" -ForegroundColor Yellow
    Write-Host "   DO NOT deploy to production until all errors are resolved" -ForegroundColor Red
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Copy .env.production.template to .env.production" -ForegroundColor White
Write-Host "2. Replace all placeholder values with real secrets" -ForegroundColor White
Write-Host "3. Run setup-production.ps1 to generate secure secrets" -ForegroundColor White
Write-Host "4. Deploy with environment variables from .env.production" -ForegroundColor White

exit $ErrorCount