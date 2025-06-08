#!/bin/bash

# Installation Verification Script
# Run this after deployment to verify everything is working correctly

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

echo -e "${BLUE}=== Crypto Airdrop Platform - Installation Verification ===${NC}"
echo

# Check system services
info "Checking system services..."

if systemctl is-active --quiet postgresql; then
    success "PostgreSQL is running"
else
    error "PostgreSQL is not running"
    echo "  Fix: sudo systemctl start postgresql"
fi

if systemctl is-active --quiet nginx; then
    success "Nginx is running"
else
    error "Nginx is not running"
    echo "  Fix: sudo systemctl start nginx"
fi

# Check PM2 application
info "Checking PM2 application..."

if pm2 describe crypto-airdrop &>/dev/null; then
    STATUS=$(pm2 describe crypto-airdrop | grep "status" | awk '{print $4}')
    if [[ "$STATUS" == "online" ]]; then
        success "Application is running in PM2"
    else
        error "Application is stopped in PM2"
        echo "  Fix: pm2 restart crypto-airdrop"
    fi
else
    error "Application not found in PM2"
    echo "  Fix: cd /var/www/crypto-airdrop && pm2 start ecosystem.config.js --env production"
fi

# Check database connection
info "Testing database connection..."

if [[ -f "/var/www/crypto-airdrop/.env.production" ]]; then
    DB_URL=$(grep DATABASE_URL /var/www/crypto-airdrop/.env.production | cut -d'=' -f2)
    if [[ -n "$DB_URL" ]]; then
        if psql "$DB_URL" -c "SELECT 1;" &>/dev/null; then
            success "Database connection successful"
        else
            error "Database connection failed"
            echo "  Check: PostgreSQL is running and credentials are correct"
        fi
    else
        error "DATABASE_URL not found in environment file"
    fi
else
    error "Environment file not found"
fi

# Check application response
info "Testing application endpoints..."

sleep 2  # Give app time to respond

if curl -s http://localhost:5000/api/categories &>/dev/null; then
    success "Application responding to API requests"
else
    warn "Application may not be responding correctly"
    echo "  Check: pm2 logs crypto-airdrop"
fi

# Check web server
info "Testing web server configuration..."

if curl -s http://localhost &>/dev/null; then
    success "Nginx proxy is working"
else
    error "Nginx proxy configuration issue"
    echo "  Check: sudo nginx -t"
fi

# Check file permissions
info "Checking file permissions..."

if [[ -d "/var/www/crypto-airdrop/public/uploads" ]]; then
    UPLOAD_PERMS=$(stat -c "%a" /var/www/crypto-airdrop/public/uploads)
    if [[ "$UPLOAD_PERMS" == "755" || "$UPLOAD_PERMS" == "775" ]]; then
        success "Upload directory permissions are correct"
    else
        warn "Upload directory permissions may need adjustment"
        echo "  Fix: chmod -R 755 /var/www/crypto-airdrop/public/uploads"
    fi
else
    error "Upload directory not found"
    echo "  Fix: mkdir -p /var/www/crypto-airdrop/public/uploads && chmod 755 /var/www/crypto-airdrop/public/uploads"
fi

# Check firewall
info "Checking firewall configuration..."

if ufw status | grep -q "Status: active"; then
    if ufw status | grep -q "80\|443\|Nginx"; then
        success "Firewall is configured correctly"
    else
        warn "Firewall may be blocking web traffic"
        echo "  Fix: sudo ufw allow 'Nginx Full'"
    fi
else
    warn "Firewall is not enabled"
    echo "  Recommendation: sudo ufw enable"
fi

# Check SSL certificate (if applicable)
info "Checking SSL configuration..."

if [[ -d "/etc/letsencrypt/live" ]]; then
    CERT_COUNT=$(find /etc/letsencrypt/live -name "cert.pem" | wc -l)
    if [[ "$CERT_COUNT" -gt 0 ]]; then
        success "SSL certificate found"
    else
        warn "SSL certificate directory exists but no certificates found"
    fi
else
    info "No SSL certificates configured (optional)"
fi

# Check backup system
info "Checking backup configuration..."

if [[ -f "/opt/crypto-backups/backup.sh" ]]; then
    if [[ -x "/opt/crypto-backups/backup.sh" ]]; then
        success "Backup script is configured"
    else
        warn "Backup script exists but is not executable"
        echo "  Fix: sudo chmod +x /opt/crypto-backups/backup.sh"
    fi
else
    warn "Backup script not found"
    echo "  Create backup script for data protection"
fi

# Check cron jobs
if crontab -l 2>/dev/null | grep -q "backup.sh"; then
    success "Automated backup is scheduled"
else
    warn "No automated backup scheduled"
    echo "  Add: (crontab -l; echo '0 2 * * * /opt/crypto-backups/backup.sh') | crontab -"
fi

# System resources
info "Checking system resources..."

MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [[ "$MEMORY_USAGE" -lt 80 ]]; then
    success "Memory usage is normal (${MEMORY_USAGE}%)"
else
    warn "High memory usage (${MEMORY_USAGE}%)"
fi

DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ "$DISK_USAGE" -lt 80 ]]; then
    success "Disk usage is normal (${DISK_USAGE}%)"
else
    warn "High disk usage (${DISK_USAGE}%)"
fi

echo
echo -e "${BLUE}=== Verification Summary ===${NC}"

# Count issues
ERRORS=$(grep -c "✗" /tmp/verification.log 2>/dev/null || echo "0")
WARNINGS=$(grep -c "⚠" /tmp/verification.log 2>/dev/null || echo "0")

if [[ "$ERRORS" -eq 0 && "$WARNINGS" -eq 0 ]]; then
    success "All checks passed! Your installation is working correctly."
elif [[ "$ERRORS" -eq 0 ]]; then
    warn "Installation is working but has $WARNINGS warnings to address."
else
    error "Found $ERRORS errors and $WARNINGS warnings that need attention."
fi

echo
info "Next steps:"
echo "1. Access your platform at: http://your-domain-or-ip"
echo "2. Login with admin/admin123 and change the password"
echo "3. Configure site settings through the admin panel"
echo "4. Add your first airdrop listing"

echo
info "For troubleshooting, check:"
echo "• Application logs: pm2 logs crypto-airdrop"
echo "• System logs: sudo journalctl -u nginx -u postgresql"
echo "• Troubleshooting guide: TROUBLESHOOTING.md"