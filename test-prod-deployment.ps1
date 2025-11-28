# =================================================================
# PRODUCTION DEPLOYMENT TEST - ZUGFAHRT APP
# Comprehensive testing script for production deployment
# =================================================================

param(
    [string]$BaseUrl = "http://localhost",
    [int]$TimeoutSeconds = 30
)

# Functions for colored output
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-Success { param($msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Test results
$TestResults = @()

function Test-Endpoint {
    param(
        [string]$Url,
        [string]$TestName,
        [int]$ExpectedStatusCode = 200,
        [string]$ExpectedContent = $null
    )
    
    try {
        Write-Info "Testing: $TestName"
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds
        
        $success = $response.StatusCode -eq $ExpectedStatusCode
        
        if ($ExpectedContent -and $success) {
            $success = $response.Content -like "*$ExpectedContent*"
        }
        
        if ($success) {
            Write-Success "$TestName - Status: $($response.StatusCode)"
            $TestResults += [PSCustomObject]@{
                Test         = $TestName
                Status       = "PASS"
                StatusCode   = $response.StatusCode
                ResponseTime = $response.Headers.'X-Response-Time'
            }
        }
        else {
            Write-Error "$TestName - Expected: $ExpectedStatusCode, Got: $($response.StatusCode)"
            $TestResults += [PSCustomObject]@{
                Test       = $TestName
                Status     = "FAIL"
                StatusCode = $response.StatusCode
                Error      = "Status code mismatch"
            }
        }
    }
    catch {
        Write-Error "$TestName - Exception: $($_.Exception.Message)"
        $TestResults += [PSCustomObject]@{
            Test       = $TestName
            Status     = "FAIL"
            StatusCode = "N/A"
            Error      = $_.Exception.Message
        }
    }
}

function Test-DockerServices {
    Write-Info "Checking Docker services status..."
    
    $services = @(
        @{Name = "zugfahrt-app"; RequiredState = "running" },
        @{Name = "zugfahrt-db"; RequiredState = "running" },
        @{Name = "zugfahrt-redis"; RequiredState = "running" },
        @{Name = "zugfahrt-nginx"; RequiredState = "running" }
    )
    
    foreach ($service in $services) {
        try {
            $status = docker ps --filter "name=$($service.Name)" --format "table {{.Status}}" | Select-Object -Skip 1
            if ($status -like "*Up*") {
                Write-Success "Service $($service.Name): Running"
                $TestResults += [PSCustomObject]@{
                    Test         = "Docker Service: $($service.Name)"
                    Status       = "PASS"
                    StatusCode   = "Running"
                    ResponseTime = $null
                }
            }
            else {
                Write-Error "Service $($service.Name): Not running"
                $TestResults += [PSCustomObject]@{
                    Test       = "Docker Service: $($service.Name)"
                    Status     = "FAIL"
                    StatusCode = "Not Running"
                    Error      = "Service not running"
                }
            }
        }
        catch {
            Write-Error "Error checking service $($service.Name): $($_.Exception.Message)"
        }
    }
}

function Test-DatabaseConnection {
    Write-Info "Testing database connection..."
    
    try {
        $result = docker-compose -f docker-compose.prod.yml exec -T db pg_isready -U zugfahrt_user
        if ($result -like "*accepting connections*") {
            Write-Success "Database connection: OK"
            $TestResults += [PSCustomObject]@{
                Test         = "Database Connection"
                Status       = "PASS"
                StatusCode   = "Connected"
                ResponseTime = $null
            }
        }
        else {
            Write-Error "Database connection: Failed"
            $TestResults += [PSCustomObject]@{
                Test       = "Database Connection"
                Status     = "FAIL"
                StatusCode = "Not Connected"
                Error      = "Database not accepting connections"
            }
        }
    }
    catch {
        Write-Error "Database connection test failed: $($_.Exception.Message)"
    }
}

function Test-RedisConnection {
    Write-Info "Testing Redis connection..."
    
    try {
        $result = docker-compose -f docker-compose.prod.yml exec -T redis redis-cli ping 2>$null
        if ($result -like "*PONG*") {
            Write-Success "Redis connection: OK"
            $TestResults += [PSCustomObject]@{
                Test         = "Redis Connection"
                Status       = "PASS"
                StatusCode   = "Connected"
                ResponseTime = $null
            }
        }
        else {
            Write-Error "Redis connection: Failed"
            $TestResults += [PSCustomObject]@{
                Test       = "Redis Connection"
                Status     = "FAIL"
                StatusCode = "Not Connected"
                Error      = "Redis not responding"
            }
        }
    }
    catch {
        Write-Error "Redis connection test failed: $($_.Exception.Message)"
    }
}

function Test-SecurityHeaders {
    Write-Info "Testing security headers..."
    
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/health" -UseBasicParsing -TimeoutSec $TimeoutSeconds
        
        $securityHeaders = @(
            "X-Frame-Options",
            "X-Content-Type-Options",
            "X-XSS-Protection",
            "Content-Security-Policy"
        )
        
        $headersPresent = 0
        foreach ($header in $securityHeaders) {
            if ($response.Headers[$header]) {
                Write-Success "Security header present: $header"
                $headersPresent++
            }
            else {
                Write-Warning "Security header missing: $header"
            }
        }
        
        $TestResults += [PSCustomObject]@{
            Test         = "Security Headers"
            Status       = if ($headersPresent -eq $securityHeaders.Count) { "PASS" } else { "PARTIAL" }
            StatusCode   = "$headersPresent/$($securityHeaders.Count) headers"
            ResponseTime = $null
        }
        
    }
    catch {
        Write-Error "Security headers test failed: $($_.Exception.Message)"
    }
}

# Main testing function
function Start-ProductionTests {
    Write-Info "🚀 Starting Production Deployment Tests for Zugfahrt App"
    Write-Info "Base URL: $BaseUrl"
    Write-Info "Timeout: $TimeoutSeconds seconds"
    Write-Host ""
    
    # Test Docker services
    Test-DockerServices
    Write-Host ""
    
    # Test database and cache connections
    Test-DatabaseConnection
    Test-RedisConnection
    Write-Host ""
    
    # Test application endpoints
    Write-Info "Testing Application Endpoints..."
    Test-Endpoint -Url "$BaseUrl/health" -TestName "Health Check" -ExpectedContent "UP"
    Test-Endpoint -Url "$BaseUrl/" -TestName "Root Endpoint" -ExpectedContent "Zugfahrt"
    Test-Endpoint -Url "$BaseUrl/actuator/health" -TestName "Actuator Health" -ExpectedContent "UP"
    Test-Endpoint -Url "$BaseUrl/actuator/info" -TestName "Actuator Info"
    Test-Endpoint -Url "$BaseUrl/actuator/prometheus" -TestName "Prometheus Metrics" -ExpectedContent "jvm_"
    Write-Host ""
    
    # Test security
    Write-Info "Testing Security..."
    Test-SecurityHeaders
    Test-Endpoint -Url "$BaseUrl/api/v1/protected" -TestName "Protected Endpoint (should be 403)" -ExpectedStatusCode 403
    Write-Host ""
    
    # Test monitoring services
    Write-Info "Testing Monitoring Services..."
    Test-Endpoint -Url "http://localhost:9090/-/healthy" -TestName "Prometheus Health"
    Test-Endpoint -Url "http://localhost:3000/api/health" -TestName "Grafana Health"
    Write-Host ""
    
    # Summary
    Write-Info "📊 Test Results Summary:"
    Write-Host ""
    
    $PassedTests = ($TestResults | Where-Object { $_.Status -eq "PASS" }).Count
    $FailedTests = ($TestResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $PartialTests = ($TestResults | Where-Object { $_.Status -eq "PARTIAL" }).Count
    $TotalTests = $TestResults.Count
    
    Write-Host "Total Tests: $TotalTests" -ForegroundColor White
    Write-Host "Passed: $PassedTests" -ForegroundColor Green
    Write-Host "Failed: $FailedTests" -ForegroundColor Red
    Write-Host "Partial: $PartialTests" -ForegroundColor Yellow
    Write-Host ""
    
    # Detailed results
    $TestResults | Format-Table -AutoSize
    
    # Overall result
    if ($FailedTests -eq 0) {
        Write-Success "🎉 All critical tests passed! Production deployment is healthy."
        return $true
    }
    elseif ($FailedTests -le 2 -and $PassedTests -ge ($TotalTests * 0.8)) {
        Write-Warning "⚠️ Most tests passed with some issues. Monitor the deployment closely."
        return $true
    }
    else {
        Write-Error "❌ Multiple critical tests failed. Check the deployment before proceeding."
        return $false
    }
}

# Performance test function
function Test-Performance {
    Write-Info "🚀 Starting Performance Tests..."
    
    try {
        # Test response time
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri "$BaseUrl/health" -UseBasicParsing
        $stopwatch.Stop()
        
        $responseTime = $stopwatch.ElapsedMilliseconds
        
        if ($responseTime -lt 1000) {
            Write-Success "Response time: ${responseTime}ms (Excellent)"
        }
        elseif ($responseTime -lt 3000) {
            Write-Warning "Response time: ${responseTime}ms (Acceptable)"
        }
        else {
            Write-Error "Response time: ${responseTime}ms (Slow)"
        }
        
        # Test concurrent requests (simple)
        Write-Info "Testing concurrent requests..."
        $jobs = @()
        for ($i = 0; $i -lt 10; $i++) {
            $jobs += Start-Job -ScriptBlock {
                param($url)
                $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
                return $response.StatusCode
            } -ArgumentList "$BaseUrl/health"
        }
        
        $results = $jobs | Wait-Job | Receive-Job
        $jobs | Remove-Job
        
        $successfulRequests = ($results | Where-Object { $_ -eq 200 }).Count
        Write-Info "Concurrent requests: $successfulRequests/10 successful"
        
        if ($successfulRequests -eq 10) {
            Write-Success "Concurrent requests test: PASS"
        }
        else {
            Write-Warning "Concurrent requests test: Some failures ($successfulRequests/10)"
        }
        
    }
    catch {
        Write-Error "Performance test failed: $($_.Exception.Message)"
    }
}

# Run the tests
$deploymentHealthy = Start-ProductionTests

# Run performance tests if deployment is healthy
if ($deploymentHealthy) {
    Write-Host ""
    Test-Performance
}

Write-Host ""
Write-Info "Production deployment testing completed!"
Write-Host ""
Write-Info "Next steps:"
Write-Host "  • Monitor application logs: docker-compose -f docker-compose.prod.yml logs -f app"
Write-Host "  • Check Grafana dashboards: http://localhost:3000"
Write-Host "  • Review Prometheus metrics: http://localhost:9090"
Write-Host "  • Set up SSL certificates for HTTPS"
Write-Host "  • Configure domain name and DNS"