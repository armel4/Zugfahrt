#!/bin/bash

# =================================================================
# PRODUCTION DEPLOYMENT SCRIPT - ZUGFAHRT APP
# Automated deployment with security checks and rollback
# =================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="zugfahrt-prod"
BACKUP_DIR="./backups"
COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Pre-deployment checks
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or not accessible"
        exit 1
    fi
    
    # Check if Docker Compose is available
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check if environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file $ENV_FILE not found. Copy from .env.example and configure."
        exit 1
    fi
    
    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Docker Compose file $COMPOSE_FILE not found"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Backup database
backup_database() {
    log_info "Creating database backup..."
    
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).sql"
    
    # Only backup if database is running
    if docker-compose -f "$COMPOSE_FILE" ps db | grep -q "Up"; then
        docker-compose -f "$COMPOSE_FILE" exec -T db pg_dump -U zugfahrt_user zugfahrt_prod > "$BACKUP_FILE"
        log_success "Database backup created: $BACKUP_FILE"
    else
        log_warning "Database not running, skipping backup"
    fi
}

# Build application
build_application() {
    log_info "Building application..."
    
    # Build with production dockerfile
    docker-compose -f "$COMPOSE_FILE" build --no-cache app
    
    log_success "Application build completed"
}

# Deploy services
deploy_services() {
    log_info "Deploying services..."
    
    # Stop existing services gracefully
    docker-compose -f "$COMPOSE_FILE" down --timeout 30
    
    # Start services in correct order
    docker-compose -f "$COMPOSE_FILE" up -d db redis
    
    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    timeout 60s bash -c 'until docker-compose -f '$COMPOSE_FILE' exec db pg_isready -U zugfahrt_user; do sleep 2; done'
    
    # Start application
    docker-compose -f "$COMPOSE_FILE" up -d app
    
    # Start reverse proxy and monitoring
    docker-compose -f "$COMPOSE_FILE" up -d nginx prometheus grafana
    
    log_success "Services deployed successfully"
}

# Health check
health_check() {
    log_info "Performing health checks..."
    
    # Wait for application to be ready
    log_info "Waiting for application to be healthy..."
    timeout 120s bash -c 'until curl -sf http://localhost:8080/health; do sleep 5; done'
    
    # Check database connection
    if docker-compose -f "$COMPOSE_FILE" exec -T db pg_isready -U zugfahrt_user >/dev/null; then
        log_success "Database health check passed"
    else
        log_error "Database health check failed"
        return 1
    fi
    
    # Check Redis connection
    if docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping >/dev/null; then
        log_success "Redis health check passed"
    else
        log_error "Redis health check failed"
        return 1
    fi
    
    # Check Nginx
    if curl -sf http://localhost/health >/dev/null; then
        log_success "Nginx health check passed"
    else
        log_error "Nginx health check failed"
        return 1
    fi
    
    log_success "All health checks passed"
}

# Rollback function
rollback() {
    log_warning "Rolling back deployment..."
    
    # Stop current deployment
    docker-compose -f "$COMPOSE_FILE" down --timeout 30
    
    # Restore from backup if available
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/backup_*.sql 2>/dev/null | head -n1)
    if [ -n "$LATEST_BACKUP" ]; then
        log_info "Restoring from backup: $LATEST_BACKUP"
        docker-compose -f "$COMPOSE_FILE" up -d db
        sleep 10
        cat "$LATEST_BACKUP" | docker-compose -f "$COMPOSE_FILE" exec -T db psql -U zugfahrt_user zugfahrt_prod
    fi
    
    log_error "Rollback completed"
}

# Cleanup old images
cleanup() {
    log_info "Cleaning up old Docker images..."
    
    docker image prune -f
    docker volume prune -f
    
    # Keep only last 5 backups
    if [ -d "$BACKUP_DIR" ]; then
        ls -t "$BACKUP_DIR"/backup_*.sql 2>/dev/null | tail -n +6 | xargs -r rm -f
    fi
    
    log_success "Cleanup completed"
}

# Show deployment status
show_status() {
    log_info "Deployment status:"
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo ""
    log_info "Application URLs:"
    echo "  • Application: http://localhost (or your domain)"
    echo "  • Health Check: http://localhost/health"
    echo "  • Prometheus: http://localhost:9090"
    echo "  • Grafana: http://localhost:3000 (admin/password from .env)"
    echo ""
    
    log_info "Logs:"
    echo "  • Application: docker-compose -f $COMPOSE_FILE logs -f app"
    echo "  • All services: docker-compose -f $COMPOSE_FILE logs -f"
}

# Main deployment function
main() {
    log_info "Starting production deployment for Zugfahrt App..."
    
    # Trap errors for rollback
    trap rollback ERR
    
    check_prerequisites
    backup_database
    build_application
    deploy_services
    
    # Remove trap after successful deployment
    trap - ERR
    
    if health_check; then
        cleanup
        show_status
        log_success "🎉 Production deployment completed successfully!"
    else
        log_error "Health checks failed, initiating rollback..."
        rollback
        exit 1
    fi
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "rollback")
        rollback
        ;;
    "status")
        show_status
        ;;
    "logs")
        docker-compose -f "$COMPOSE_FILE" logs -f "${2:-}"
        ;;
    "backup")
        backup_database
        ;;
    *)
        echo "Usage: $0 {deploy|rollback|status|logs [service]|backup}"
        exit 1
        ;;
esac