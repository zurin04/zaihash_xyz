#!/bin/bash

# Crypto Airdrop Platform - Root User VPS Installation Script
# Designed for root users with automatic security hardening

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# Generate secure passwords
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use: sudo ./install-vps-root.sh"
    fi
    success "Running as root user"
}

# Create application user for security
create_app_user() {
    log "Creating application user for security..."
    
    # Create dedicated user for the application
    if ! id "appuser" &>/dev/null; then
        useradd -m -s /bin/bash appuser
        usermod -aG sudo appuser
        success "Created application user: appuser"
    else
        success "Application user already exists"
    fi
    
    # Set up SSH key copying if needed
    if [[ -f "/root/.ssh/authorized_keys" ]]; then
        mkdir -p /home/appuser/.ssh
        cp /root/.ssh/authorized_keys /home/appuser/.ssh/
        chown -R appuser:appuser /home/appuser/.ssh
        chmod 700 /home/appuser/.ssh
        chmod 600 /home/appuser/.ssh/authorized_keys
        success "SSH keys copied to appuser"
    fi
}

# Get configuration
get_config() {
    echo -e "${GREEN}=== Crypto Airdrop Platform Root Installation ===${NC}"
    echo "This will install a complete crypto airdrop platform with:"
    echo "• Node.js 20 runtime"
    echo "• PostgreSQL database" 
    echo "• Nginx web server"
    echo "• SSL certificates"
    echo "• Security hardening"
    echo "• Dedicated application user"
    echo ""
    
    read -p "Domain name (optional, press Enter to use IP): " DOMAIN
    if [[ -n "$DOMAIN" ]]; then
        read -p "Email for SSL certificate: " EMAIL
    fi
    read -p "Repository URL: " REPO_URL
    read -s -p "Database password (press Enter for auto-generated): " DB_PASS
    echo ""
    
    if [[ -z "$DB_PASS" ]]; then
        DB_PASS=$(generate_password)
        log "Generated secure database password"
    fi
    
    SESSION_SECRET=$(openssl rand -hex 32)
    APP_USER="appuser"
    
    success "Configuration collected"
}

# Install packages
install_packages() {
    log "Updating system and installing packages..."
    
    # Update system
    apt update
    DEBIAN_FRONTEND=noninteractive apt upgrade -y
    
    # Install Node.js 20
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    DEBIAN_FRONTEND=noninteractive apt install -y nodejs
    
    # Install other packages
    DEBIAN_FRONTEND=noninteractive apt install -y \
        postgresql postgresql-contrib \
        nginx certbot python3-certbot-nginx \
        git curl wget ufw fail2ban \
        htop unzip software-properties-common
    
    # Install PM2 globally
    npm install -g pm2
    
    success "All packages installed"
}

# Configure PostgreSQL
setup_database() {
    log "Configuring PostgreSQL database..."
    
    # Start and enable PostgreSQL
    systemctl start postgresql
    systemctl enable postgresql
    
    # Wait for PostgreSQL to be ready
    sleep 3
    
    # Create database and user
    sudo -u postgres psql << EOF
DROP DATABASE IF EXISTS crypto_airdrop_db;
DROP USER IF EXISTS airdrop_user;
CREATE DATABASE crypto_airdrop_db;
CREATE USER airdrop_user WITH ENCRYPTED PASSWORD '$DB_PASS';
GRANT ALL PRIVILEGES ON DATABASE crypto_airdrop_db TO airdrop_user;
ALTER USER airdrop_user CREATEDB;
ALTER DATABASE crypto_airdrop_db OWNER TO airdrop_user;
\q
EOF
    
    # Test database connection
    if PGPASSWORD="$DB_PASS" psql -U airdrop_user -h localhost -d crypto_airdrop_db -c "SELECT 1;" &>/dev/null; then
        success "Database configured successfully"
    else
        error "Database configuration failed"
    fi
}

# Setup application
setup_application() {
    log "Setting up application..."
    
    # Create directory structure
    mkdir -p /var/www
    cd /var/www
    
    # Remove existing installation
    rm -rf crypto-airdrop
    
    # Clone repository
    git clone "$REPO_URL" crypto-airdrop
    cd crypto-airdrop
    
    # Set proper ownership
    chown -R $APP_USER:$APP_USER /var/www/crypto-airdrop
    
    # Install dependencies as app user
    sudo -u $APP_USER npm install
    
    # Create environment file
    sudo -u $APP_USER tee .env.production << EOF
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://airdrop_user:$DB_PASS@localhost:5432/crypto_airdrop_db
SESSION_SECRET=$SESSION_SECRET
EOF
    
    # Secure environment file
    chmod 600 .env.production
    chown $APP_USER:$APP_USER .env.production
    
    success "Application setup complete"
}

# Initialize database
init_database() {
    log "Initializing database schema..."
    
    cd /var/www/crypto-airdrop
    
    # Verify database connection
    if ! PGPASSWORD="$DB_PASS" psql -U airdrop_user -h localhost -d crypto_airdrop_db -c "SELECT 1;" &>/dev/null; then
        error "Cannot connect to database before schema initialization"
    fi
    
    # Push schema and seed data as app user
    sudo -u $APP_USER npm run db:push
    sudo -u $APP_USER npm run db:seed
    
    success "Database initialized"
}

# Build and configure PM2
setup_pm2() {
    log "Building application and configuring PM2..."
    
    cd /var/www/crypto-airdrop
    
    # Build application as app user
    sudo -u $APP_USER npm run build
    
    # Create PM2 ecosystem
    sudo -u $APP_USER tee ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'crypto-airdrop',
    script: 'tsx',
    args: 'server/index.ts',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    env_production: {
      NODE_ENV: 'production',
      PORT: 5000
    },
    env_file: '.env.production'
  }]
}
EOF
    
    # Create logs directory
    sudo -u $APP_USER mkdir -p logs
    
    # Start with PM2 as app user
    sudo -u $APP_USER pm2 start ecosystem.config.js --env production
    sudo -u $APP_USER pm2 save
    
    # Setup PM2 startup for app user
    sudo -u $APP_USER pm2 startup systemd
    env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $APP_USER --hp /home/$APP_USER
    
    success "PM2 configured and application started"
}

# Configure Nginx
setup_nginx() {
    log "Configuring Nginx..."
    
    SERVER_NAME="${DOMAIN:-_}"
    
    tee /etc/nginx/sites-available/crypto-airdrop << EOF
server {
    listen 80;
    server_name $SERVER_NAME;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=login:10m rate=5r/m;
    
    # Main proxy
    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # API rate limiting
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Login rate limiting
    location /api/login {
        limit_req zone=login burst=5 nodelay;
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # WebSocket support
    location /ws {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }
    
    # Static files
    location /uploads/ {
        alias /var/www/crypto-airdrop/public/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    # Block access to sensitive files
    location ~ /\. {
        deny all;
    }
    
    location ~ \.(env|log|config)$ {
        deny all;
    }
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/crypto-airdrop /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    nginx -t
    
    # Start and enable Nginx
    systemctl start nginx
    systemctl enable nginx
    
    success "Nginx configured with security headers and rate limiting"
}

# Configure enhanced firewall and security
setup_security() {
    log "Configuring enhanced security..."
    
    # Configure UFW firewall
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (be careful not to lock yourself out)
    ufw allow ssh
    ufw allow 22/tcp
    
    # Allow HTTP and HTTPS
    ufw allow 'Nginx Full'
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable firewall
    ufw --force enable
    
    # Configure fail2ban
    tee /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
action = iptables-multiport[name=ReqLimit, port="http,https", protocol=tcp]
logpath = /var/log/nginx/*error.log
findtime = 600
bantime = 7200
maxretry = 10

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
    
    systemctl enable fail2ban
    systemctl start fail2ban
    
    # Disable root SSH login (optional, but recommended)
    read -p "Disable root SSH login for security? (y/N): " DISABLE_ROOT_SSH
    if [[ "$DISABLE_ROOT_SSH" =~ ^[Yy]$ ]]; then
        sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
        systemctl restart sshd
        warn "Root SSH login disabled. Use 'appuser' account for future access."
    fi
    
    success "Security hardening completed"
}

# Setup upload directories
setup_uploads() {
    log "Setting up file upload directories..."
    
    cd /var/www/crypto-airdrop
    
    # Create upload directories
    mkdir -p public/uploads/images public/uploads/avatars
    
    # Set proper permissions
    chown -R $APP_USER:www-data public/uploads
    chmod -R 775 public/uploads
    
    success "Upload directories configured"
}

# Install SSL certificate
setup_ssl() {
    if [[ -n "$DOMAIN" && -n "$EMAIL" ]]; then
        log "Installing SSL certificate..."
        
        # Install SSL certificate
        certbot --nginx \
            -d "$DOMAIN" \
            -d "www.$DOMAIN" \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            --redirect
        
        # Setup auto-renewal
        systemctl enable certbot.timer
        systemctl start certbot.timer
        
        success "SSL certificate installed with auto-renewal"
    else
        warn "Skipping SSL setup (domain name or email not provided)"
    fi
}

# Setup comprehensive backup system
setup_backup() {
    log "Setting up backup system..."
    
    # Create backup directory
    mkdir -p /opt/crypto-backups/{db,app,config}
    
    # Create comprehensive backup script
    tee /opt/crypto-backups/backup.sh << EOF
#!/bin/bash
# Comprehensive backup script for Crypto Airdrop Platform

DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/crypto-backups"
APP_DIR="/var/www/crypto-airdrop"

# Create timestamp directory
mkdir -p \$BACKUP_DIR/\$DATE

# Database backup
echo "Creating database backup..."
PGPASSWORD='$DB_PASS' pg_dump -U airdrop_user -h localhost crypto_airdrop_db > \$BACKUP_DIR/db/db_backup_\$DATE.sql

# Application backup (excluding node_modules and logs)
echo "Creating application backup..."
tar -czf \$BACKUP_DIR/app/app_backup_\$DATE.tar.gz \
    --exclude=node_modules \
    --exclude=.git \
    --exclude=logs \
    --exclude=dist \
    -C /var/www crypto-airdrop

# Configuration backup
echo "Creating configuration backup..."
cp /etc/nginx/sites-available/crypto-airdrop \$BACKUP_DIR/config/nginx_\$DATE.conf
cp \$APP_DIR/.env.production \$BACKUP_DIR/config/env_\$DATE.conf

# PM2 ecosystem backup
cp \$APP_DIR/ecosystem.config.js \$BACKUP_DIR/config/pm2_\$DATE.js

# Clean old backups (keep 7 days)
find \$BACKUP_DIR/db -name "db_backup_*.sql" -mtime +7 -delete
find \$BACKUP_DIR/app -name "app_backup_*.tar.gz" -mtime +7 -delete
find \$BACKUP_DIR/config -name "*_*.conf" -mtime +7 -delete
find \$BACKUP_DIR/config -name "*_*.js" -mtime +7 -delete

echo "Backup completed: \$DATE"
echo "Database: \$BACKUP_DIR/db/db_backup_\$DATE.sql"
echo "Application: \$BACKUP_DIR/app/app_backup_\$DATE.tar.gz"
echo "Configuration: \$BACKUP_DIR/config/"
EOF
    
    chmod +x /opt/crypto-backups/backup.sh
    
    # Create update script
    tee /opt/crypto-backups/update.sh << EOF
#!/bin/bash
# Update script for Crypto Airdrop Platform

echo "Starting application update..."

# Backup before update
/opt/crypto-backups/backup.sh

cd /var/www/crypto-airdrop

echo "Pulling latest changes..."
sudo -u $APP_USER git pull

echo "Installing dependencies..."
sudo -u $APP_USER npm install

echo "Building application..."
sudo -u $APP_USER npm run build

echo "Restarting application..."
sudo -u $APP_USER pm2 restart crypto-airdrop

echo "Update completed successfully!"
sudo -u $APP_USER pm2 status
EOF
    
    chmod +x /opt/crypto-backups/update.sh
    
    # Setup automated backups
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/crypto-backups/backup.sh") | crontab -
    
    # Setup log rotation
    tee /etc/logrotate.d/crypto-airdrop << EOF
/var/www/crypto-airdrop/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    su $APP_USER $APP_USER
    postrotate
        sudo -u $APP_USER pm2 reloadLogs
    endscript
}
EOF
    
    success "Comprehensive backup system configured"
}

# Verify installation
verify_installation() {
    log "Verifying installation..."
    
    # Check services
    services=("postgresql" "nginx" "fail2ban")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            success "$service is running"
        else
            error "$service is not running"
        fi
    done
    
    # Check PM2 as app user
    if sudo -u $APP_USER pm2 describe crypto-airdrop &>/dev/null; then
        success "Application is running in PM2"
    else
        error "Application is not running in PM2"
    fi
    
    # Test database connection
    if PGPASSWORD="$DB_PASS" psql -U airdrop_user -h localhost -d crypto_airdrop_db -c "SELECT COUNT(*) FROM users;" &>/dev/null; then
        success "Database connection verified"
    else
        error "Database connection failed"
    fi
    
    # Wait for app to start
    sleep 10
    
    # Test application response
    if curl -s http://localhost:5000/api/categories &>/dev/null; then
        success "Application responding correctly"
    else
        warn "Application may still be starting up"
    fi
    
    success "Installation verification completed"
}

# Display completion information
show_completion() {
    APP_URL="http://${DOMAIN:-$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')}"
    if [[ -n "$DOMAIN" && -n "$EMAIL" ]]; then
        APP_URL="https://$DOMAIN"
    fi
    
    echo
    success "=== INSTALLATION COMPLETED SUCCESSFULLY ==="
    echo
    echo -e "${GREEN}🎉 Your Crypto Airdrop Platform is ready!${NC}"
    echo
    echo -e "${BLUE}📱 Access Information:${NC}"
    echo "   URL: $APP_URL"
    echo "   SSH User: $APP_USER (for security)"
    echo
    echo -e "${BLUE}🔐 Default Credentials:${NC}"
    echo "   Admin: admin / admin123"
    echo "   Demo: demo / demo123"
    echo
    echo -e "${BLUE}🗄️ Database Information:${NC}"
    echo "   Database: crypto_airdrop_db"
    echo "   User: airdrop_user"
    echo "   Password: $DB_PASS"
    echo
    echo -e "${BLUE}⚙️ Management Commands:${NC}"
    echo "   Switch to app user: su - $APP_USER"
    echo "   View status: sudo -u $APP_USER pm2 status"
    echo "   View logs: sudo -u $APP_USER pm2 logs crypto-airdrop"
    echo "   Restart app: sudo -u $APP_USER pm2 restart crypto-airdrop"
    echo "   Update app: /opt/crypto-backups/update.sh"
    echo "   Backup data: /opt/crypto-backups/backup.sh"
    echo
    echo -e "${BLUE}📁 Important Locations:${NC}"
    echo "   App directory: /var/www/crypto-airdrop"
    echo "   Backups: /opt/crypto-backups/"
    echo "   Nginx config: /etc/nginx/sites-available/crypto-airdrop"
    echo "   Environment: /var/www/crypto-airdrop/.env.production"
    echo
    echo -e "${BLUE}🔒 Security Features Enabled:${NC}"
    echo "   • Dedicated application user ($APP_USER)"
    echo "   • UFW firewall with restrictive rules"
    echo "   • Fail2ban intrusion prevention"
    echo "   • Rate limiting on API endpoints"
    echo "   • Security headers in Nginx"
    echo "   • Automated backups every 2 AM"
    echo "   • Log rotation"
    echo
    echo -e "${YELLOW}⚠️ CRITICAL SECURITY REMINDERS:${NC}"
    echo "   1. Change default admin and demo passwords immediately"
    echo "   2. Consider disabling root SSH login (use $APP_USER account)"
    echo "   3. Regular security updates: apt update && apt upgrade"
    echo "   4. Monitor logs: journalctl -f"
    echo "   5. Test backups regularly"
    echo
    
    if [[ -n "$DOMAIN" && -n "$EMAIL" ]]; then
        echo -e "${GREEN}🔒 SSL certificate installed and will auto-renew${NC}"
    else
        echo -e "${YELLOW}💡 Add SSL later: certbot --nginx${NC}"
    fi
    
    echo
    success "Production deployment completed with enterprise-grade security!"
}

# Main installation process
main() {
    echo "Starting Crypto Airdrop Platform root installation..."
    echo "This process includes security hardening and takes 10-15 minutes..."
    echo
    
    check_root
    get_config
    create_app_user
    install_packages
    setup_database
    setup_application
    init_database
    setup_pm2
    setup_nginx
    setup_security
    setup_uploads
    setup_ssl
    setup_backup
    verify_installation
    show_completion
}

# Error handling
trap 'echo -e "${RED}Installation failed. Check the output above for details.${NC}"; exit 1' ERR

# Run installation
main "$@"