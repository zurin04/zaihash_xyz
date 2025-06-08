# VPS Setup Guide - Crypto Airdrop Platform

Complete guide to deploy your crypto airdrop platform on any VPS. This guide eliminates common PostgreSQL and setup errors.

## Requirements

- Fresh Ubuntu 20.04/22.04 VPS with at least 2GB RAM
- Root or sudo access
- Domain name (optional)
- Email address (for SSL certificates)

## One-Click Installation

Run this single command on your VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/your-repo/crypto-airdrop-platform/main/install-vps.sh | bash
```

## Step-by-Step Manual Installation

### 1. Initial Server Setup

Connect to your VPS:
```bash
ssh root@your-server-ip
```

Update system:
```bash
apt update && apt upgrade -y
```

### 2. Install Required Software

```bash
# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
apt install -y nodejs

# Install PostgreSQL and other packages
apt install -y postgresql postgresql-contrib nginx git ufw certbot python3-certbot-nginx curl

# Install PM2 globally
npm install -g pm2
```

### 3. Configure PostgreSQL (Error-Free Method)

```bash
# Start PostgreSQL
systemctl start postgresql
systemctl enable postgresql

# Switch to postgres user and setup database
sudo -u postgres psql << 'EOF'
CREATE DATABASE crypto_airdrop_db;
CREATE USER airdrop_user WITH ENCRYPTED PASSWORD 'SecurePassword123!';
GRANT ALL PRIVILEGES ON DATABASE crypto_airdrop_db TO airdrop_user;
ALTER USER airdrop_user CREATEDB;
\q
EOF

# Test database connection
sudo -u postgres psql -c "SELECT version();"
```

### 4. Download and Setup Application

```bash
# Create app directory
mkdir -p /var/www
cd /var/www

# Clone repository
git clone https://github.com/your-repo/crypto-airdrop-platform.git
cd crypto-airdrop-platform

# Install dependencies
npm install

# Create production environment
cat > .env.production << 'EOF'
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://airdrop_user:SecurePassword123!@localhost:5432/crypto_airdrop_db
SESSION_SECRET=your-super-secret-session-key-here-make-it-very-long-and-random
EOF

# Set secure permissions
chmod 600 .env.production
```

### 5. Initialize Database

```bash
# Push database schema
npm run db:push

# Seed initial data
npm run db:seed

# Build application
npm run build
```

### 6. Configure PM2 Process Manager

```bash
# Create PM2 configuration
cat > ecosystem.config.js << 'EOF'
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
pm2 start ecosystem.config.js --env production
pm2 save
pm2 startup
```

### 7. Configure Nginx Reverse Proxy

```bash
# Create Nginx configuration
cat > /etc/nginx/sites-available/crypto-airdrop << 'EOF'
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;

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

    # WebSocket support
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
ln -s /etc/nginx/sites-available/crypto-airdrop /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and start Nginx
nginx -t
systemctl start nginx
systemctl enable nginx
```

### 8. Configure Firewall

```bash
# Setup UFW firewall
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable
```

### 9. Install SSL Certificate (Optional)

If you have a domain:
```bash
certbot --nginx -d your-domain.com -d www.your-domain.com
```

## Default Access

After setup, access your platform:
- **URL**: http://your-domain.com or http://your-server-ip
- **Admin**: username `admin`, password `admin123`
- **Demo**: username `demo`, password `demo123`

Change these passwords immediately after first login.

## Management Commands

```bash
# View application status
pm2 status

# View logs
pm2 logs crypto-airdrop

# Restart application
pm2 restart crypto-airdrop

# Stop application
pm2 stop crypto-airdrop

# Database backup
pg_dump -U airdrop_user -h localhost crypto_airdrop_db > backup.sql
```

## Troubleshooting

### PostgreSQL Issues

If database connection fails:
```bash
# Check PostgreSQL status
systemctl status postgresql

# Check if database exists
sudo -u postgres psql -l | grep crypto_airdrop_db

# Reset user password
sudo -u postgres psql -c "ALTER USER airdrop_user PASSWORD 'SecurePassword123!';"

# Test connection
PGPASSWORD='SecurePassword123!' psql -U airdrop_user -h localhost crypto_airdrop_db -c "SELECT 1;"
```

### Application Issues

If app won't start:
```bash
# Check detailed logs
pm2 logs crypto-airdrop --lines 100

# Check if port is available
netstat -tlnp | grep :5000

# Restart all services
systemctl restart postgresql
pm2 restart crypto-airdrop
systemctl restart nginx
```

### Nginx Issues

If web server problems:
```bash
# Test configuration
nginx -t

# Check logs
tail -f /var/log/nginx/error.log

# Restart Nginx
systemctl restart nginx
```

## Security Checklist

- [ ] Change default admin passwords
- [ ] Update system packages regularly
- [ ] Enable automatic security updates
- [ ] Monitor application logs
- [ ] Setup regular database backups
- [ ] Use strong database passwords
- [ ] Enable fail2ban for SSH protection

## Backup Strategy

Create automated backup:
```bash
# Create backup script
cat > /opt/backup.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p /opt/backups
pg_dump -U airdrop_user -h localhost crypto_airdrop_db > /opt/backups/db_$DATE.sql
find /opt/backups -name "db_*.sql" -mtime +7 -delete
EOF

chmod +x /opt/backup.sh

# Schedule daily backup
echo "0 2 * * * /opt/backup.sh" | crontab -
```

This guide provides a reliable, tested deployment process that avoids common PostgreSQL configuration errors.