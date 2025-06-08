#!/bin/bash

# Crypto Airdrop Platform - Automated VPS Deployment Script
# Compatible with Ubuntu 20.04/22.04

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Generate secure password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check Ubuntu version
    if ! grep -q "Ubuntu" /etc/os-release; then
        print_error "This script requires Ubuntu 20.04 or 22.04"
    fi
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges. Please ensure you can run sudo commands."
    fi
    
    print_success "System requirements check passed"
}

# Get configuration from user
get_configuration() {
    echo -e "${GREEN}=== Crypto Airdrop Platform VPS Deployment ===${NC}"
    echo
    echo "This script will install and configure:"
    echo "• Node.js 20"
    echo "• PostgreSQL database"
    echo "• Nginx web server"
    echo "• PM2 process manager"
    echo "• SSL certificate (optional)"
    echo "• Firewall configuration"
    echo
    
    read -p "Enter your domain name (e.g., example.com) or press Enter to use IP: " DOMAIN_NAME
    read -p "Enter your email for SSL certificate (required if using domain): " EMAIL
    read -p "Enter PostgreSQL password (or press Enter to auto-generate): " DB_PASSWORD
    read -p "Enter Git repository URL: " REPO_URL
    
    # Validate repository URL
    if [[ -z "$REPO_URL" ]]; then
        print_error "Git repository URL is required"
    fi
    
    # Generate passwords if not provided
    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=$(generate_password)
        print_status "Generated database password: $DB_PASSWORD"
    fi
    
    SESSION_SECRET=$(generate_password)
    APP_PORT=5000
    
    echo
    print_status "Configuration Summary:"
    echo "• Domain: ${DOMAIN_NAME:-'Using IP address'}"
    echo "• Email: ${EMAIL:-'Not provided'}"
    echo "• Repository: $REPO_URL"
    echo "• App Port: $APP_PORT"
    echo "• Database: crypto_airdrop_db"
    echo "• Database User: airdrop_user"
    echo
    
    read -p "Continue with installation? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_error "Installation cancelled by user"
    fi
}

# Update system packages
update_system() {
    print_status "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    print_success "System updated successfully"
}

# Install required packages
install_packages() {
    print_status "Installing required packages..."
    
    # Install Node.js 20
    print_status "Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
    
    # Install other packages
    sudo apt install -y \
        postgresql \
        postgresql-contrib \
        nginx \
        git \
        ufw \
        certbot \
        python3-certbot-nginx \
        curl \
        wget \
        unzip
    
    # Install PM2
    print_status "Installing PM2..."
    sudo npm install -g pm2
    
    print_success "All packages installed successfully"
}

# Configure PostgreSQL
setup_database() {
    print_status "Configuring PostgreSQL database..."
    
    # Start and enable PostgreSQL
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    # Create database and user
    sudo -u postgres psql << EOF
CREATE DATABASE crypto_airdrop_db;
CREATE USER airdrop_user WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE crypto_airdrop_db TO airdrop_user;
ALTER USER airdrop_user CREATEDB;
ALTER DATABASE crypto_airdrop_db OWNER TO airdrop_user;
\q
EOF
    
    # Test database connection
    if PGPASSWORD="$DB_PASSWORD" psql -U airdrop_user -h localhost -d crypto_airdrop_db -c "SELECT 1;" >/dev/null 2>&1; then
        print_success "Database configured successfully"
    else
        print_error "Database configuration failed"
    fi
}

# Setup application
setup_application() {
    print_status "Setting up application..."
    
    # Create application directory
    sudo mkdir -p /var/www
    cd /var/www
    
    # Remove existing directory if it exists
    if [[ -d "crypto-airdrop" ]]; then
        sudo rm -rf crypto-airdrop
    fi
    
    # Clone repository
    print_status "Cloning repository..."
    sudo git clone "$REPO_URL" crypto-airdrop
    cd crypto-airdrop
    
    # Change ownership
    sudo chown -R $USER:$USER /var/www/crypto-airdrop
    
    # Install dependencies
    print_status "Installing Node.js dependencies..."
    npm install
    
    # Create production environment file
    print_status "Creating environment configuration..."
    cat > .env.production << EOF
NODE_ENV=production
PORT=$APP_PORT
DATABASE_URL=postgresql://airdrop_user:$DB_PASSWORD@localhost:5432/crypto_airdrop_db
SESSION_SECRET=$SESSION_SECRET
EOF
    
    # Secure environment file
    chmod 600 .env.production
    
    print_success "Application setup completed"
}

# Setup database schema
setup_schema() {
    print_status "Setting up database schema..."
    
    cd /var/www/crypto-airdrop
    
    # Push database schema
    npm run db:push
    
    # Seed initial data
    npm run db:seed
    
    print_success "Database schema and initial data created"
}

# Build application
build_application() {
    print_status "Building application..."
    
    cd /var/www/crypto-airdrop
    npm run build
    
    print_success "Application built successfully"
}

# Configure PM2
setup_pm2() {
    print_status "Configuring PM2 process manager..."
    
    cd /var/www/crypto-airdrop
    
    # Create PM2 ecosystem file
    cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'crypto-airdrop-platform',
    script: 'tsx',
    args: 'server/index.ts',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env_production: {
      NODE_ENV: 'production',
      PORT: $APP_PORT
    },
    env_file: '.env.production'
  }]
}
EOF
    
    # Start application
    pm2 start ecosystem.config.js --env production
    
    # Save PM2 configuration
    pm2 save
    
    # Setup PM2 startup
    pm2 startup systemd
    sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp $HOME
    
    print_success "PM2 configured and application started"
}

# Configure Nginx
setup_nginx() {
    print_status "Configuring Nginx web server..."
    
    # Create Nginx configuration
    SERVER_NAME="${DOMAIN_NAME:-_}"
    
    sudo tee /etc/nginx/sites-available/crypto-airdrop << EOF
server {
    listen 80;
    server_name $SERVER_NAME;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Main application
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_connect_timeout       60s;
        proxy_send_timeout          60s;
        proxy_read_timeout          60s;
    }

    # WebSocket support for real-time chat
    location /ws {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    # Static files (if any)
    location /uploads/ {
        alias /var/www/crypto-airdrop/public/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Health check
    location /health {
        proxy_pass http://localhost:$APP_PORT;
        access_log off;
    }
}
EOF
    
    # Enable site
    sudo ln -sf /etc/nginx/sites-available/crypto-airdrop /etc/nginx/sites-enabled/
    
    # Remove default site
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test Nginx configuration
    sudo nginx -t
    
    # Start and enable Nginx
    sudo systemctl start nginx
    sudo systemctl enable nginx
    
    print_success "Nginx configured successfully"
}

# Configure firewall
setup_firewall() {
    print_status "Configuring UFW firewall..."
    
    # Reset UFW to defaults
    sudo ufw --force reset
    
    # Set default policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Allow SSH
    sudo ufw allow ssh
    sudo ufw allow 22/tcp
    
    # Allow HTTP and HTTPS
    sudo ufw allow 'Nginx Full'
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    
    # Enable firewall
    sudo ufw --force enable
    
    print_success "Firewall configured successfully"
}

# Create upload directories
setup_uploads() {
    print_status "Setting up file upload directories..."
    
    cd /var/www/crypto-airdrop
    
    # Create upload directories
    mkdir -p public/uploads/images
    mkdir -p public/uploads/avatars
    
    # Set proper permissions
    chmod -R 755 public/uploads
    chown -R $USER:www-data public/uploads
    
    print_success "Upload directories configured"
}

# Install SSL certificate
setup_ssl() {
    if [[ -n "$DOMAIN_NAME" && -n "$EMAIL" ]]; then
        print_status "Installing SSL certificate..."
        
        # Install SSL certificate
        sudo certbot --nginx \
            -d "$DOMAIN_NAME" \
            -d "www.$DOMAIN_NAME" \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            --redirect
        
        # Test auto-renewal
        sudo certbot renew --dry-run
        
        print_success "SSL certificate installed and auto-renewal configured"
    else
        print_warning "Skipping SSL setup (domain name or email not provided)"
    fi
}

# Setup backup system
setup_backup() {
    print_status "Setting up backup system..."
    
    # Create backup directory
    sudo mkdir -p /opt/crypto-airdrop/backups
    
    # Create backup script
    sudo tee /opt/crypto-airdrop/backup.sh << EOF
#!/bin/bash
# Crypto Airdrop Platform Backup Script

DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/crypto-airdrop/backups"
APP_DIR="/var/www/crypto-airdrop"

# Create backup directory
mkdir -p \$BACKUP_DIR

# Database backup
echo "Creating database backup..."
PGPASSWORD='$DB_PASSWORD' pg_dump -U airdrop_user -h localhost crypto_airdrop_db > \$BACKUP_DIR/db_backup_\$DATE.sql

# Application backup (excluding node_modules)
echo "Creating application backup..."
tar -czf \$BACKUP_DIR/app_backup_\$DATE.tar.gz -C /var/www crypto-airdrop --exclude=node_modules --exclude=.git

# Clean old backups (keep last 7 days)
find \$BACKUP_DIR -name "db_backup_*.sql" -mtime +7 -delete
find \$BACKUP_DIR -name "app_backup_*.tar.gz" -mtime +7 -delete

echo "Backup completed: \$DATE"
echo "Database backup: \$BACKUP_DIR/db_backup_\$DATE.sql"
echo "Application backup: \$BACKUP_DIR/app_backup_\$DATE.tar.gz"
EOF
    
    # Make backup script executable
    sudo chmod +x /opt/crypto-airdrop/backup.sh
    
    # Create update script
    sudo tee /opt/crypto-airdrop/update.sh << EOF
#!/bin/bash
# Crypto Airdrop Platform Update Script

cd /var/www/crypto-airdrop

echo "Pulling latest changes..."
git pull

echo "Installing dependencies..."
npm install

echo "Building application..."
npm run build

echo "Restarting application..."
pm2 restart crypto-airdrop-platform

echo "Update completed successfully!"
EOF
    
    sudo chmod +x /opt/crypto-airdrop/update.sh
    
    # Setup daily backup cron job (2 AM)
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/crypto-airdrop/backup.sh") | crontab -
    
    print_success "Backup system configured (daily backups at 2 AM)"
}

# Verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    # Check services
    if ! sudo systemctl is-active --quiet postgresql; then
        print_error "PostgreSQL is not running"
    fi
    
    if ! sudo systemctl is-active --quiet nginx; then
        print_error "Nginx is not running"
    fi
    
    # Check PM2
    if ! pm2 describe crypto-airdrop-platform >/dev/null 2>&1; then
        print_error "PM2 application is not running"
    fi
    
    # Check database connection
    if ! PGPASSWORD="$DB_PASSWORD" psql -U airdrop_user -h localhost -d crypto_airdrop_db -c "SELECT COUNT(*) FROM users;" >/dev/null 2>&1; then
        print_error "Database connection failed"
    fi
    
    # Check application response
    sleep 5  # Give app time to start
    if ! curl -s http://localhost:$APP_PORT/api/categories >/dev/null; then
        print_warning "Application may not be responding correctly"
    fi
    
    print_success "Installation verification completed"
}

# Display final information
show_completion_info() {
    local APP_URL
    if [[ -n "$DOMAIN_NAME" ]]; then
        if [[ -n "$EMAIL" ]]; then
            APP_URL="https://$DOMAIN_NAME"
        else
            APP_URL="http://$DOMAIN_NAME"
        fi
    else
        APP_URL="http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_VPS_IP')"
    fi
    
    echo
    print_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    echo -e "${GREEN}🎉 Your Crypto Airdrop Platform is now live!${NC}"
    echo
    echo -e "${BLUE}📱 Application Access:${NC}"
    echo "   URL: $APP_URL"
    echo
    echo -e "${BLUE}🔐 Default Login Credentials:${NC}"
    echo "   Admin: admin / admin123"
    echo "   Demo:  demo / demo123"
    echo
    echo -e "${BLUE}🗄️  Database Information:${NC}"
    echo "   Database: crypto_airdrop_db"
    echo "   User: airdrop_user"
    echo "   Password: $DB_PASSWORD"
    echo
    echo -e "${BLUE}⚙️  Management Commands:${NC}"
    echo "   View logs:    pm2 logs crypto-airdrop-platform"
    echo "   Restart app:  pm2 restart crypto-airdrop-platform"
    echo "   App status:   pm2 status"
    echo "   Update app:   sudo /opt/crypto-airdrop/update.sh"
    echo "   Backup data:  sudo /opt/crypto-airdrop/backup.sh"
    echo
    echo -e "${BLUE}📁 Important Files:${NC}"
    echo "   App directory:    /var/www/crypto-airdrop"
    echo "   Environment:      /var/www/crypto-airdrop/.env.production"
    echo "   Nginx config:     /etc/nginx/sites-available/crypto-airdrop"
    echo "   Backup location:  /opt/crypto-airdrop/backups"
    echo
    echo -e "${YELLOW}⚠️  IMPORTANT SECURITY REMINDERS:${NC}"
    echo "   1. Change default admin and demo passwords immediately"
    echo "   2. Secure your .env.production file (already set to 600)"
    echo "   3. Regular backups are scheduled daily at 2 AM"
    echo "   4. Keep your system updated with: sudo apt update && sudo apt upgrade"
    echo
    
    if [[ -n "$DOMAIN_NAME" && -n "$EMAIL" ]]; then
        echo -e "${GREEN}🔒 SSL certificate is installed and auto-renewing${NC}"
    else
        echo -e "${YELLOW}💡 To add SSL later: sudo certbot --nginx${NC}"
    fi
    
    echo
    print_success "Happy crypto hunting! 🚀"
}

# Main installation function
main() {
    echo "Starting Crypto Airdrop Platform deployment..."
    echo "This will take approximately 5-10 minutes..."
    echo
    
    check_requirements
    get_configuration
    update_system
    install_packages
    setup_database
    setup_application
    setup_schema
    build_application
    setup_pm2
    setup_nginx
    setup_firewall
    setup_uploads
    setup_ssl
    setup_backup
    verify_installation
    show_completion_info
}

# Error handling
trap 'print_error "An error occurred during installation. Check the output above for details."' ERR

# Run main installation
main "$@"