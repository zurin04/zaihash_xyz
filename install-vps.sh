#!/bin/bash

# Crypto Airdrop Platform - Zero-Error VPS Installation Script
# Designed to eliminate PostgreSQL and common deployment issues

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

# Check requirements
check_system() {
    log "Checking system requirements..."
    
    if [[ $EUID -eq 0 ]]; then
        error "Do not run as root. Use a sudo user instead."
    fi
    
    if ! command -v sudo &> /dev/null; then
        error "sudo is required but not installed"
    fi
    
    if ! grep -q "Ubuntu" /etc/os-release; then
        error "This script requires Ubuntu 20.04 or 22.04"
    fi
    
    success "System requirements met"
}

# Get user configuration
get_config() {
    echo -e "${GREEN}=== Crypto Airdrop Platform Installation ===${NC}"
    echo "This will install a complete crypto airdrop platform with:"
    echo "• Node.js 20 runtime"
    echo "• PostgreSQL database" 
    echo "• Nginx web server"
    echo "• SSL certificates"
    echo "• Process management"
    echo ""
    
    read -p "Domain name (optional, press Enter to use IP): " DOMAIN
    if [[ -n "$DOMAIN" ]]; then
        read -p "Email for SSL certificate: " EMAIL
    fi
    read -p "Repository URL: " REPO_URL
    read -s -p "Database password (press Enter for auto-generated): " DB_PASS
    echo ""
    
    if [[ -z "$DB_PASS" ]]; then
        DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)
        log "Generated secure database password"
    fi
    
    SESSION_SECRET=$(openssl rand -hex 32)
    
    success "Configuration collected"
}

# Install packages with error handling
install_packages() {
    log "Updating system and installing packages..."
    
    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
    
    # Install Node.js 20
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo DEBIAN_FRONTEND=noninteractive apt install -y nodejs
    
    # Install other packages
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        postgresql postgresql-contrib \
        nginx certbot python3-certbot-nginx \
        git curl wget ufw fail2ban
    
    # Install PM2
    sudo npm install -g pm2
    
    success "All packages installed"
}

# Configure PostgreSQL with proper error handling
setup_database() {
    log "Configuring PostgreSQL database..."
    
    # Ensure PostgreSQL is running
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    # Wait for PostgreSQL to be ready
    sleep 3
    
    # Create database and user with proper escaping
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

# Setup application with proper permissions
setup_application() {
    log "Setting up application..."
    
    # Create directory structure
    sudo mkdir -p /var/www
    cd /var/www
    
    # Remove existing installation
    sudo rm -rf crypto-airdrop
    
    # Clone repository
    sudo git clone "$REPO_URL" crypto-airdrop
    cd crypto-airdrop
    
    # Set ownership
    sudo chown -R $USER:$USER /var/www/crypto-airdrop
    
    # Install dependencies
    npm install
    
    # Create environment file
    cat > .env.production << EOF
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://airdrop_user:$DB_PASS@localhost:5432/crypto_airdrop_db
SESSION_SECRET=$SESSION_SECRET
EOF
    
    # Secure environment file
    chmod 600 .env.production
    
    success "Application setup complete"
}

# Initialize database schema
init_database() {
    log "Initializing database schema..."
    
    cd /var/www/crypto-airdrop
    
    # Verify database connection before schema operations
    if ! PGPASSWORD="$DB_PASS" psql -U airdrop_user -h localhost -d crypto_airdrop_db -c "SELECT 1;" &>/dev/null; then
        error "Cannot connect to database before schema initialization"
    fi
    
    # Push schema
    npm run db:push
    
    # Seed data
    npm run db:seed
    
    success "Database initialized"
}

# Build and configure PM2
setup_pm2() {
    log "Building application and configuring PM2..."
    
    cd /var/www/crypto-airdrop
    
    # Build application
    npm run build
    
    # Create PM2 ecosystem
    cat > ecosystem.config.js << EOF
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
    mkdir -p logs
    
    # Start with PM2
    pm2 start ecosystem.config.js --env production
    pm2 save
    
    # Setup startup script
    pm2 startup systemd
    sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp $HOME
    
    success "PM2 configured and application started"
}

# Configure Nginx with WebSocket support
setup_nginx() {
    log "Configuring Nginx..."
    
    SERVER_NAME="${DOMAIN:-_}"
    
    sudo tee /etc/nginx/sites-available/crypto-airdrop << EOF
server {
    listen 80;
    server_name $SERVER_NAME;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
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
    }
}
EOF
    
    # Enable site
    sudo ln -sf /etc/nginx/sites-available/crypto-airdrop /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    sudo nginx -t
    
    # Start Nginx
    sudo systemctl start nginx
    sudo systemctl enable nginx
    
    success "Nginx configured"
}

# Configure firewall
setup_firewall() {
    log "Configuring firewall..."
    
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow 'Nginx Full'
    sudo ufw --force enable
    
    success "Firewall configured"
}

# Create upload directories
setup_uploads() {
    log "Setting up upload directories..."
    
    cd /var/www/crypto-airdrop
    mkdir -p public/uploads/images public/uploads/avatars
    chmod -R 755 public/uploads
    chown -R $USER:www-data public/uploads
    
    success "Upload directories ready"
}

# Install SSL if domain provided
setup_ssl() {
    if [[ -n "$DOMAIN" && -n "$EMAIL" ]]; then
        log "Installing SSL certificate..."
        
        sudo certbot --nginx \
            -d "$DOMAIN" \
            -d "www.$DOMAIN" \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            --redirect
        
        success "SSL certificate installed"
    fi
}

# Setup backup system
setup_backup() {
    log "Setting up backup system..."
    
    sudo mkdir -p /opt/crypto-backups
    
    sudo tee /opt/crypto-backups/backup.sh << EOF
#!/bin/bash
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/crypto-backups"

# Database backup
PGPASSWORD='$DB_PASS' pg_dump -U airdrop_user -h localhost crypto_airdrop_db > \$BACKUP_DIR/db_\$DATE.sql

# Clean old backups (keep 7 days)
find \$BACKUP_DIR -name "db_*.sql" -mtime +7 -delete

echo "Backup completed: \$DATE"
EOF
    
    sudo chmod +x /opt/crypto-backups/backup.sh
    
    # Schedule daily backup
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/crypto-backups/backup.sh") | crontab -
    
    success "Backup system configured"
}

# Verify installation
verify_installation() {
    log "Verifying installation..."
    
    # Check services
    if ! sudo systemctl is-active --quiet postgresql; then
        error "PostgreSQL is not running"
    fi
    
    if ! sudo systemctl is-active --quiet nginx; then
        error "Nginx is not running"
    fi
    
    # Check PM2
    if ! pm2 describe crypto-airdrop &>/dev/null; then
        error "Application is not running in PM2"
    fi
    
    # Test database
    if ! PGPASSWORD="$DB_PASS" psql -U airdrop_user -h localhost -d crypto_airdrop_db -c "SELECT COUNT(*) FROM users;" &>/dev/null; then
        error "Database connection test failed"
    fi
    
    # Wait for app to start
    sleep 10
    
    # Test application response
    if ! curl -s http://localhost:5000/api/categories &>/dev/null; then
        warn "Application may still be starting up"
    fi
    
    success "Installation verified"
}

# Display completion info
show_completion() {
    APP_URL="http://${DOMAIN:-$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')}"
    if [[ -n "$DOMAIN" && -n "$EMAIL" ]]; then
        APP_URL="https://$DOMAIN"
    fi
    
    echo ""
    success "=== INSTALLATION COMPLETED ==="
    echo ""
    echo -e "${GREEN}🎉 Your Crypto Airdrop Platform is ready!${NC}"
    echo ""
    echo -e "${BLUE}Access your platform:${NC}"
    echo "URL: $APP_URL"
    echo ""
    echo -e "${BLUE}Default credentials:${NC}"
    echo "Admin: admin / admin123"
    echo "Demo: demo / demo123"
    echo ""
    echo -e "${BLUE}Database info:${NC}"
    echo "Database: crypto_airdrop_db"
    echo "User: airdrop_user"
    echo "Password: $DB_PASS"
    echo ""
    echo -e "${BLUE}Management commands:${NC}"
    echo "View status: pm2 status"
    echo "View logs: pm2 logs crypto-airdrop"
    echo "Restart app: pm2 restart crypto-airdrop"
    echo "Backup data: sudo /opt/crypto-backups/backup.sh"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Change default passwords after first login!${NC}"
    echo ""
}

# Main installation process
main() {
    echo "Starting Crypto Airdrop Platform installation..."
    echo "This process takes about 5-10 minutes..."
    echo ""
    
    check_system
    get_config
    install_packages
    setup_database
    setup_application
    init_database
    setup_pm2
    setup_nginx
    setup_firewall
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