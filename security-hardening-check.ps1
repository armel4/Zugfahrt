param([switch]$Verbose)

Write-Host "ZUGFAHRT PRO - PRODUCTION SECURITY HARDENING" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$ErrorCount = 0
$WarningCount = 0

function Write-Status($Message, $Type) {
    if ($Type -eq "PASS") { 
        Write-Host "✅ $Message" -ForegroundColor Green 
    }
    elseif ($Type -eq "FAIL") { 
        Write-Host "❌ $Message" -ForegroundColor Red
        $script:ErrorCount++ 
    }
    elseif ($Type -eq "WARN") { 
        Write-Host "⚠️ $Message" -ForegroundColor Yellow
        $script:WarningCount++ 
    }
    else { 
        Write-Host "ℹ️ $Message" -ForegroundColor Cyan 
    }
}

# 1. Check for exposed secrets
Write-Host "Checking for exposed secrets..."
$SecretsFound = $false

Get-ChildItem -Recurse -File -Include "*.java", "*.properties", "*.yml", "*.md" | Where-Object {
    $_.FullName -notlike "*target*"
} | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains("sk-") -and $content.Length -gt 30) {
        if (-not $content.Contains("your_actual") -and -not $content.Contains("REPLACE_WITH")) {
            Write-Status "CRITICAL: Potential exposed secret found in $($_.Name)" "FAIL"
            $SecretsFound = $true
        }
    }
}

if (-not $SecretsFound) {
    Write-Status "No hardcoded secrets found" "PASS"
}

# 2. Check production configuration
Write-Host "`nChecking production configuration..."
$ProdConfig = "src/main/resources/application-prod.properties"
if (Test-Path $ProdConfig) {
    Write-Status "Production configuration file found" "PASS"
}
else {
    Write-Status "Production configuration file not found" "WARN"
}

# 3. Check SecurityConfig
Write-Host "`nChecking security configuration..."
$SecurityConfig = "src/main/java/com/karibu/tech/config/SecurityConfig.java"
if (Test-Path $SecurityConfig) {
    $content = Get-Content $SecurityConfig -Raw
    
    if ($content.Contains("BCryptPasswordEncoder")) {
        Write-Status "BCrypt password encoder configured" "PASS"
    }
    else {
        Write-Status "BCrypt password encoder not found" "FAIL"
    }
    
    if ($content.Contains("STATELESS")) {
        Write-Status "Stateless session management configured" "PASS"
    }
    else {
        Write-Status "Stateless session management recommended" "WARN"
    }
}
else {
    Write-Status "SecurityConfig.java not found" "FAIL"
}

# 4. Generate production secrets template
Write-Host "`nGenerating production secrets template..."

$envTemplate = "# ZUGFAHRT PRO - PRODUCTION ENVIRONMENT VARIABLES`n"
$envTemplate += "# Database Configuration`n"
$envTemplate += "DB_URL=jdbc:postgresql://your-db-host:5432/your-db-name`n"
$envTemplate += "DB_USERNAME=your_db_username`n"
$envTemplate += "DB_PASSWORD=YOUR_STRONG_DB_PASSWORD`n`n"
$envTemplate += "# JWT Configuration`n"
$envTemplate += "JWT_SECRET=YOUR_256BIT_SECRET_HERE`n"
$envTemplate += "JWT_EXPIRATION=1800000`n`n"
$envTemplate += "# CORS Configuration`n"
$envTemplate += "CORS_ALLOWED_ORIGINS=https://your-frontend.netlify.app`n`n"
$envTemplate += "# OpenAI Configuration`n"
$envTemplate += "OPENAI_API_KEY=sk-proj-your_actual_openai_key_here`n"
$envTemplate += "OPENAI_MODEL=gpt-4o-2024-11-20`n"

$envTemplate | Out-File -FilePath ".env.production.template" -Encoding UTF8
Write-Status "Production secrets template created: .env.production.template" "PASS"

# 5. Final summary
Write-Host "`n===================================================="
Write-Host "SECURITY VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "===================================================="

if ($ErrorCount -eq 0 -and $WarningCount -eq 0) {
    Write-Host "🎉 SECURITY HARDENING COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "   All automated checks passed" -ForegroundColor Green
}
elseif ($ErrorCount -eq 0) {
    Write-Host "✅ SECURITY HARDENING MOSTLY COMPLETED" -ForegroundColor Yellow
    Write-Host "   $WarningCount warnings found - review recommended" -ForegroundColor Yellow
}
else {
    Write-Host "❌ SECURITY HARDENING INCOMPLETE" -ForegroundColor Red
    Write-Host "   $ErrorCount critical errors must be fixed" -ForegroundColor Red
    Write-Host "   $WarningCount warnings should be reviewed" -ForegroundColor Red
    Write-Host "   DO NOT deploy to production until all errors are resolved" -ForegroundColor Red
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Copy .env.production.template to .env.production" -ForegroundColor White
Write-Host "2. Replace placeholder values with real secrets" -ForegroundColor White
Write-Host "3. Run setup-production.ps1 to generate secure secrets" -ForegroundColor White

exit $ErrorCount