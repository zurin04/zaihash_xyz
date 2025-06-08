#!/bin/bash

# Crypto Airdrop Platform - Contabo VPS Root Installation
# Non-interactive version with sensible defaults

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

# Configuration with defaults
REPO_URL="https://github.com/zurin04/Airdropzaihash.git"
DB_PASS="AirdropSecure$(openssl rand -base64 16 | tr -d "=+/")"
SESSION_SECRET=$(openssl rand -hex 32)
APP_USER="appuser"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo -e "${GREEN}=== Contabo VPS Crypto Airdrop Platform Installation ===${NC}"
echo "Repository: $REPO_URL"
echo "Server IP: $SERVER_IP"
echo "Database Password: $DB_PASS"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
fi

log "Starting Contabo VPS deployment..."

# Create application user
log "Creating application user..."
if ! id "$APP_USER" &>/dev/null; then
    useradd -m -s /bin/bash $APP_USER
    usermod -aG sudo $APP_USER
    success "Created user: $APP_USER"
fi

# Update system
log "Updating system packages..."
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y

# Install Node.js 20
log "Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
DEBIAN_FRONTEND=noninteractive apt install -y nodejs

# Install packages
log "Installing required packages..."
DEBIAN_FRONTEND=noninteractive apt install -y \
    postgresql postgresql-contrib \
    nginx git ufw \
    curl wget unzip

# Install PM2
npm install -g pm2

# Configure PostgreSQL
log "Configuring PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

sleep 3

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

# Test database
if PGPASSWORD="$DB_PASS" psql -U airdrop_user -h localhost -d crypto_airdrop_db -c "SELECT 1;" &>/dev/null; then
    success "Database configured successfully"
else
    error "Database configuration failed"
fi

# Setup application
log "Setting up application..."
mkdir -p /var/www
cd /var/www
rm -rf crypto-airdrop
git clone "$REPO_URL" crypto-airdrop
cd crypto-airdrop
chown -R $APP_USER:$APP_USER /var/www/crypto-airdrop

# Install dependencies
sudo -u $APP_USER npm install

# Create environment
sudo -u $APP_USER tee .env.production << EOF
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://airdrop_user:$DB_PASS@localhost:5432/crypto_airdrop_db
SESSION_SECRET=$SESSION_SECRET
EOF

chmod 600 .env.production

# Initialize database
log "Initializing database..."
sudo -u $APP_USER npm run db:push
sudo -u $APP_USER npm run db:seed
sudo -u $APP_USER npm run build

# Configure PM2
log "Configuring PM2..."
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
    env_production: {
      NODE_ENV: 'production',
      PORT: 5000
    },
    env_file: '.env.production'
  }]
}
EOF

sudo -u $APP_USER mkdir -p logs
sudo -u $APP_USER pm2 start ecosystem.config.js --env production
sudo -u $APP_USER pm2 save

# Setup PM2 startup
sudo -u $APP_USER pm2 startup systemd
env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $APP_USER --hp /home/$APP_USER

# Configure Nginx
log "Configuring Nginx..."
tee /etc/nginx/sites-available/crypto-airdrop << EOF
server {
    listen 80;
    server_name $SERVER_IP;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
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
    }
    
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
    
    location /uploads/ {
        alias /var/www/crypto-airdrop/public/uploads/;
        expires 30d;
    }
}
EOF

ln -sf /etc/nginx/sites-available/crypto-airdrop /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl start nginx
systemctl enable nginx

# Configure firewall
log "Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable

# Setup uploads
log "Setting up upload directories..."
cd /var/www/crypto-airdrop
mkdir -p public/uploads/images public/uploads/avatars
chown -R $APP_USER:www-data public/uploads
chmod -R 775 public/uploads

# Create backup system
log "Setting up backup system..."
mkdir -p /opt/crypto-backups

tee /opt/crypto-backups/backup.sh << EOF
#!/bin/bash
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/crypto-backups"
PGPASSWORD='$DB_PASS' pg_dump -U airdrop_user -h localhost crypto_airdrop_db > \$BACKUP_DIR/db_backup_\$DATE.sql
tar -czf \$BACKUP_DIR/app_backup_\$DATE.tar.gz --exclude=node_modules --exclude=.git -C /var/www crypto-airdrop
find \$BACKUP_DIR -name "db_backup_*.sql" -mtime +7 -delete
find \$BACKUP_DIR -name "app_backup_*.tar.gz" -mtime +7 -delete
echo "Backup completed: \$DATE"
EOF

chmod +x /opt/crypto-backups/backup.sh
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/crypto-backups/backup.sh") | crontab -

# Verify installation
log "Verifying installation..."

# Check services
for service in postgresql nginx; do
    if systemctl is-active --quiet $service; then
        success "$service is running"
    else
        error "$service is not running"
    fi
done

# Check PM2
if sudo -u $APP_USER pm2 describe crypto-airdrop &>/dev/null; then
    success "Application is running in PM2"
else
    error "Application is not running in PM2"
fi

# Wait for app
sleep 10

# Test application
if curl -s http://localhost:5000/api/categories &>/dev/null; then
    success "Application responding correctly"
else
    warn "Application may still be starting"
fi

# Show completion info
echo
success "=== INSTALLATION COMPLETED ==="
echo
echo -e "${GREEN}Your Crypto Airdrop Platform is ready!${NC}"
echo
echo -e "${BLUE}Access Information:${NC}"
echo "URL: http://$SERVER_IP"
echo "Admin: admin / admin123"
echo "Demo: demo / demo123"
echo
echo -e "${BLUE}Database:${NC}"
echo "Database: crypto_airdrop_db"
echo "User: airdrop_user"
echo "Password: $DB_PASS"
echo
echo -e "${BLUE}Management:${NC}"
echo "Switch to app user: su - $APP_USER"
echo "View status: sudo -u $APP_USER pm2 status"
echo "View logs: sudo -u $APP_USER pm2 logs crypto-airdrop"
echo "Restart: sudo -u $APP_USER pm2 restart crypto-airdrop"
echo "Backup: /opt/crypto-backups/backup.sh"
echo
echo -e "${YELLOW}Important: Change default passwords after login!${NC}"
echo
echo -e "${GREEN}Installation completed successfully!${NC}"