# Root User VPS Installation Guide

Complete installation guide for root users with enhanced security features and automatic hardening.

## Quick Installation for Root Users

Run this single command as root:

```bash
curl -fsSL https://raw.githubusercontent.com/your-repo/crypto-airdrop-platform/main/install-vps-root.sh | bash
```

## What This Script Does

### Security Enhancements
- Creates dedicated application user (`appuser`) for running the platform
- Configures UFW firewall with restrictive rules
- Sets up fail2ban for intrusion prevention
- Implements Nginx rate limiting
- Adds comprehensive security headers
- Optional root SSH login disabling

### Application Setup
- Installs Node.js 20, PostgreSQL, and Nginx
- Configures PostgreSQL with encrypted passwords
- Sets up PM2 process management
- Creates automated backup system
- Implements log rotation
- Configures SSL certificates (if domain provided)

### Directory Structure Created
```
/var/www/crypto-airdrop/          # Application files
/opt/crypto-backups/              # Backup system
├── backup.sh                     # Daily backup script
├── update.sh                     # Application update script
├── db/                          # Database backups
├── app/                         # Application backups
└── config/                      # Configuration backups
```

## Manual Root Installation Steps

If you prefer manual installation:

### 1. System Preparation
```bash
# Update system
apt update && apt upgrade -y

# Create application user
useradd -m -s /bin/bash appuser
usermod -aG sudo appuser
```

### 2. Install Required Software
```bash
# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install other packages
apt install -y postgresql postgresql-contrib nginx git ufw fail2ban certbot python3-certbot-nginx

# Install PM2
npm install -g pm2
```

### 3. Configure PostgreSQL
```bash
systemctl start postgresql
systemctl enable postgresql

# Create database (replace PASSWORD with secure password)
sudo -u postgres psql << 'EOF'
CREATE DATABASE crypto_airdrop_db;
CREATE USER airdrop_user WITH ENCRYPTED PASSWORD 'YOUR_SECURE_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE crypto_airdrop_db TO airdrop_user;
ALTER USER airdrop_user CREATEDB;
ALTER DATABASE crypto_airdrop_db OWNER TO airdrop_user;
\q
EOF
```

### 4. Application Setup
```bash
# Clone repository
mkdir -p /var/www
cd /var/www
git clone YOUR_REPO_URL crypto-airdrop
cd crypto-airdrop

# Set ownership
chown -R appuser:appuser /var/www/crypto-airdrop

# Install dependencies as appuser
sudo -u appuser npm install

# Create environment file
sudo -u appuser tee .env.production << 'EOF'
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://airdrop_user:YOUR_SECURE_PASSWORD@localhost:5432/crypto_airdrop_db
SESSION_SECRET=YOUR_SESSION_SECRET
EOF

chmod 600 .env.production
```

### 5. Initialize Database
```bash
cd /var/www/crypto-airdrop
sudo -u appuser npm run db:push
sudo -u appuser npm run db:seed
sudo -u appuser npm run build
```

### 6. Configure PM2
```bash
# Create PM2 config as appuser
sudo -u appuser tee ecosystem.config.js << 'EOF'
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

# Start application
sudo -u appuser pm2 start ecosystem.config.js --env production
sudo -u appuser pm2 save
sudo -u appuser pm2 startup systemd
```

### 7. Configure Nginx with Security
```bash
tee /etc/nginx/sites-available/crypto-airdrop << 'EOF'
server {
    listen 80;
    server_name your-domain.com;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
    
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /api/login {
        limit_req zone=login burst=5 nodelay;
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /ws {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/crypto-airdrop /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl start nginx
systemctl enable nginx
```

### 8. Configure Security
```bash
# Setup firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable

# Configure fail2ban
tee /etc/fail2ban/jail.local << 'EOF'
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
maxretry = 3
bantime = 3600
EOF

systemctl enable fail2ban
systemctl start fail2ban
```

### 9. Setup SSL (if using domain)
```bash
certbot --nginx -d your-domain.com -d www.your-domain.com --non-interactive --agree-tos --email your-email@example.com
```

### 10. Create Backup System
```bash
mkdir -p /opt/crypto-backups

tee /opt/crypto-backups/backup.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/crypto-backups"

# Database backup
PGPASSWORD='YOUR_DB_PASSWORD' pg_dump -U airdrop_user -h localhost crypto_airdrop_db > $BACKUP_DIR/db_backup_$DATE.sql

# Application backup
tar -czf $BACKUP_DIR/app_backup_$DATE.tar.gz --exclude=node_modules --exclude=.git -C /var/www crypto-airdrop

# Clean old backups
find $BACKUP_DIR -name "db_backup_*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "app_backup_*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
EOF

chmod +x /opt/crypto-backups/backup.sh

# Schedule daily backups
(crontab -l; echo "0 2 * * * /opt/crypto-backups/backup.sh") | crontab -
```

## Access and Management

### Default Credentials
- **Admin**: `admin` / `admin123`
- **Demo**: `demo` / `demo123`

### Management Commands
```bash
# Switch to application user
su - appuser

# Application management (as appuser)
pm2 status
pm2 logs crypto-airdrop
pm2 restart crypto-airdrop

# System management (as root)
systemctl status nginx postgresql fail2ban
/opt/crypto-backups/backup.sh
/opt/crypto-backups/update.sh
```

### Security Best Practices

1. **Change default passwords immediately**
2. **Use the appuser account for daily operations**
3. **Consider disabling root SSH login**
4. **Monitor fail2ban logs**: `fail2ban-client status`
5. **Regular security updates**: `apt update && apt upgrade`
6. **Monitor application logs**: `sudo -u appuser pm2 logs crypto-airdrop`

### File Permissions
- Application files: `appuser:appuser`
- Upload directories: `appuser:www-data` with 775 permissions
- Environment file: 600 permissions (appuser only)
- Backup scripts: 755 permissions (root)

## Troubleshooting

### Service Issues
```bash
# Check all services
systemctl status postgresql nginx fail2ban

# Check application
sudo -u appuser pm2 status
sudo -u appuser pm2 logs crypto-airdrop --lines 50
```

### Database Issues
```bash
# Test connection
PGPASSWORD='your_password' psql -U airdrop_user -h localhost crypto_airdrop_db -c "SELECT 1;"

# Check PostgreSQL logs
tail -f /var/log/postgresql/postgresql-*-main.log
```

### Security Monitoring
```bash
# Check firewall status
ufw status verbose

# Check fail2ban status
fail2ban-client status
fail2ban-client status nginx-limit-req

# Check blocked IPs
fail2ban-client get nginx-limit-req banip
```

This root user installation provides enterprise-grade security while maintaining ease of management through the dedicated application user account.