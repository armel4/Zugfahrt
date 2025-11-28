# ZUGFAHRT PRO - PRODUCTION SETUP SCRIPT
# =====================================
# This script generates secure production configuration
# with cryptographically strong secrets for deployment.
#
# Author: Security Engineering Team
# Date: November 28, 2025
# Version: 2.1

param(
    [Parameter(Mandatory = $false)]
    [string]$Domain = "your-app.netlify.app",
    
    [Parameter(Mandatory = $false)]
    [string]$DatabaseHost = "your-db-host.neon.tech",
    
    [switch]$GenerateSecrets
)

Write-Host "ZUGFAHRT PRO - PRODUCTION SETUP" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan
Write-Host ""

# Function to generate cryptographically secure random string
function Generate-SecureSecret([int]$Length = 64) {
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $rng.GetBytes($bytes)
    return [System.Convert]::ToBase64String($bytes) -replace '[+/=]', ''
}

# Function to generate JWT secret (256-bit minimum)
function Generate-JwtSecret() {
    $bytes = New-Object byte[] 32 # 256 bits
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $rng.GetBytes($bytes)
    return [System.Convert]::ToBase64String($bytes)
}

if ($GenerateSecrets) {
    Write-Host "🔐 Generating cryptographically secure secrets..." -ForegroundColor Green
    
    $JwtSecret = Generate-JwtSecret
    $DatabasePassword = Generate-SecureSecret -Length 32
    
    Write-Host "✅ Generated 256-bit JWT secret" -ForegroundColor Green
    Write-Host "✅ Generated secure database password" -ForegroundColor Green
    
    # Create production environment file
    $ProductionEnv = @"
# ZUGFAHRT PRO - PRODUCTION ENVIRONMENT VARIABLES
# ===============================================
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# SECURITY: Keep this file secure and never commit to version control

# Database Configuration
DB_URL=jdbc:postgresql://$DatabaseHost/neondb?sslmode=require
DB_USERNAME=neondb_owner
DB_PASSWORD=$DatabasePassword

# JWT Configuration (256-bit cryptographic security)
JWT_SECRET=$JwtSecret
JWT_EXPIRATION=1800000

# CORS Configuration
CORS_ALLOWED_ORIGINS=https://$Domain
FRONTEND_URL=https://$Domain

# OpenAI Configuration (SET YOUR REAL KEY)
OPENAI_API_KEY=sk-proj-REPLACE_WITH_YOUR_ACTUAL_OPENAI_KEY
OPENAI_MODEL=gpt-4o-2024-11-20

# Email Configuration (SET YOUR REAL VALUES)
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=your-email@gmail.com
MAIL_PASSWORD=your_gmail_app_password_here
MAIL_FROM=your-email@gmail.com
APP_NAME=Zugfahrt Pro

# Security Settings
CSRF_ENABLED=true
SSL_ENABLED=false

# Server Configuration
PORT=8080
SPRING_PROFILES_ACTIVE=prod
LOG_FILE=/var/log/zugfahrt-app.log
"@

    $ProductionEnv | Out-File -FilePath ".env.production" -Encoding UTF8
    Write-Host "✅ Created .env.production with secure secrets" -ForegroundColor Green
}

# Create production docker-compose
$DockerComposeProd = @"
version: '3.8'

services:
  zugfahrt-app:
    build: .
    ports:
      - "8080:8080"
    environment:
      # Database
      DB_URL: ${'$'}{DB_URL}
      DB_USERNAME: ${'$'}{DB_USERNAME}
      DB_PASSWORD: ${'$'}{DB_PASSWORD}
      
      # JWT
      JWT_SECRET: ${'$'}{JWT_SECRET}
      JWT_EXPIRATION: ${'$'}{JWT_EXPIRATION}
      
      # CORS
      CORS_ALLOWED_ORIGINS: ${'$'}{CORS_ALLOWED_ORIGINS}
      FRONTEND_URL: ${'$'}{FRONTEND_URL}
      
      # OpenAI
      OPENAI_API_KEY: ${'$'}{OPENAI_API_KEY}
      OPENAI_MODEL: ${'$'}{OPENAI_MODEL}
      
      # Email
      MAIL_HOST: ${'$'}{MAIL_HOST}
      MAIL_PORT: ${'$'}{MAIL_PORT}
      MAIL_USERNAME: ${'$'}{MAIL_USERNAME}
      MAIL_PASSWORD: ${'$'}{MAIL_PASSWORD}
      MAIL_FROM: ${'$'}{MAIL_FROM}
      APP_NAME: ${'$'}{APP_NAME}
      
      # Security
      CSRF_ENABLED: ${'$'}{CSRF_ENABLED}
      
      # Server
      PORT: ${'$'}{PORT}
      SPRING_PROFILES_ACTIVE: prod
    
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/v1/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
"@

$DockerComposeProd | Out-File -FilePath "docker-compose.prod.yml" -Encoding UTF8
Write-Host "✅ Created docker-compose.prod.yml" -ForegroundColor Green

# Create production start script
$StartScript = @"
#!/bin/bash
# ZUGFAHRT PRO - PRODUCTION START SCRIPT
# =====================================

echo "🚀 Starting Zugfahrt Pro in production mode..."

# Load environment variables
if [ -f .env.production ]; then
    echo "📋 Loading production environment variables..."
    export `$(cat .env.production | xargs)
else
    echo "❌ Error: .env.production file not found!"
    echo "   Run setup-production.ps1 first to generate secrets"
    exit 1
fi

# Validate critical environment variables
if [ -z "`$JWT_SECRET" ] || [ "`$JWT_SECRET" == "YOUR_256BIT_CRYPTOGRAPHICALLY_RANDOM_SECRET_HERE" ]; then
    echo "❌ Error: JWT_SECRET not properly configured!"
    exit 1
fi

if [ -z "`$DB_PASSWORD" ] || [ "`$DB_PASSWORD" == "YOUR_STRONG_DB_PASSWORD" ]; then
    echo "❌ Error: DB_PASSWORD not properly configured!"
    exit 1
fi

if [ -z "`$OPENAI_API_KEY" ] || [ "`$OPENAI_API_KEY" == "sk-proj-REPLACE_WITH_YOUR_ACTUAL_OPENAI_KEY" ]; then
    echo "⚠️  Warning: OPENAI_API_KEY not configured - AI features will not work"
fi

echo "✅ Environment validation passed"
echo "🐳 Starting with Docker Compose..."

docker-compose -f docker-compose.prod.yml up -d

echo "🎉 Zugfahrt Pro started successfully!"
echo "📊 Health check: http://localhost:8080/api/v1/actuator/health"
echo "🔍 Logs: docker-compose -f docker-compose.prod.yml logs -f"
"@

$StartScript | Out-File -FilePath "start-production.sh" -Encoding UTF8
Write-Host "✅ Created start-production.sh" -ForegroundColor Green

Write-Host "`n🎯 PRODUCTION SETUP COMPLETE!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green

if ($GenerateSecrets) {
    Write-Host "✅ Secure secrets generated in .env.production" -ForegroundColor Green
    Write-Host "⚠️  IMPORTANT: Update OPENAI_API_KEY and email settings manually" -ForegroundColor Yellow
}

Write-Host "`n📋 Next steps:" -ForegroundColor Cyan
Write-Host "1. Edit .env.production with your real OpenAI API key" -ForegroundColor White
Write-Host "2. Update email configuration (Gmail app password)" -ForegroundColor White
Write-Host "3. Update database connection details" -ForegroundColor White
Write-Host "4. Deploy with: docker-compose -f docker-compose.prod.yml up -d" -ForegroundColor White
Write-Host "5. Or use start-production.sh on Linux/Mac" -ForegroundColor White

Write-Host "`n🔐 Security reminders:" -ForegroundColor Red
Write-Host "• Never commit .env.production to version control" -ForegroundColor White
Write-Host "• Keep your secrets secure and rotate them regularly" -ForegroundColor White
Write-Host "• Use HTTPS in production" -ForegroundColor White
Write-Host "• Monitor security logs regularly" -ForegroundColor White