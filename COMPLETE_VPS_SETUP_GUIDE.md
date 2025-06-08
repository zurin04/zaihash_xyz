# Complete VPS Setup Guide - Crypto Airdrop Platform

This guide provides a step-by-step process to deploy the crypto airdrop platform on any VPS (Virtual Private Server). Perfect for beginners with no prior server experience.

## What You'll Need

1. **VPS Server** - Ubuntu 20.04 or 22.04 (recommended providers: DigitalOcean, Linode, Vultr)
2. **Domain Name** (optional but recommended) - Point it to your VPS IP address
3. **SSH Access** - Terminal/command line access to your server
4. **Basic Information:**
   - Your VPS IP address
   - Root/sudo user access
   - Your domain name (if using one)
   - Email address (for SSL certificates)

## Pre-Installation Checklist

- [ ] VPS is running Ubuntu 20.04 or 22.04
- [ ] You can SSH into your server as root or sudo user
- [ ] Domain name is pointed to your VPS IP (if using domain)
- [ ] Ports 80, 443, and 5000 are available

## One-Click Installation Script

### Step 1: Download and Run the Installation Script

SSH into your VPS and run this single command:

```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/crypto-airdrop-platform/main/deploy.sh | bash
```

**Or for manual setup, follow the detailed steps below:**

## Manual Installation Guide

### Step 1: Connect to Your VPS

Open terminal and connect to your server:

```bash
ssh root@your-vps-ip-address
# Or if using a user account:
ssh your-username@your-vps-ip-address
```

### Step 2: Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 3: Install Required Software

```bash
# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install PostgreSQL
sudo apt install -y postgresql postgresql-contrib

# Install Nginx (web server)
sudo apt install -y nginx

# Install PM2 (process manager)
sudo npm install -g pm2

# Install Git
sudo apt install -y git

# Install Certbot (for SSL certificates)
sudo apt install -y certbot python3-certbot-nginx

# Install UFW (firewall)
sudo apt install -y ufw
```

### Step 4: Configure PostgreSQL Database

```bash
# Start PostgreSQL service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create database and user
sudo -u postgres psql << EOF
CREATE DATABASE crypto_airdrop_db;
CREATE USER airdrop_user WITH PASSWORD 'your-secure-password-here';
GRANT ALL PRIVILEGES ON DATABASE crypto_airdrop_db TO airdrop_user;
ALTER USER airdrop_user CREATEDB;
\q
EOF
```

**Important:** Replace `your-secure-password-here` with a strong password!

### Step 5: Clone and Setup Application

```bash
# Create application directory
sudo mkdir -p /var/www
cd /var/www

# Clone the repository
sudo git clone https://github.com/yourusername/crypto-airdrop-platform.git crypto-airdrop
cd crypto-airdrop

# Change ownership to current user
sudo chown -R $USER:$USER /var/www/crypto-airdrop

# Install dependencies
npm install

# Create production environment file
cat > .env.production << EOF
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://airdrop_user:your-secure-password-here@localhost:5432/crypto_airdrop_db
SESSION_SECRET=$(openssl rand -base64 32)
EOF
```

### Step 6: Setup Database Schema

```bash
# Push database schema
npm run db:push

# Seed initial data
npm run db:seed
```

### Step 7: Build Application

```bash
# Build the application
npm run build
```

### Step 8: Configure PM2 Process Manager

Create PM2 configuration:

```bash
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
      PORT: 5000
    },
    env_file: '.env.production'
  }]
}
EOF
```

Start the application:

```bash
# Start application with PM2
pm2 start ecosystem.config.js --env production

# Save PM2 configuration
pm2 save

# Setup PM2 to start on boot
pm2 startup
# Follow the instructions shown by PM2
```

### Step 9: Configure Nginx Web Server

Create Nginx configuration:

```bash
sudo tee /etc/nginx/sites-available/crypto-airdrop << EOF
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;

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

    # WebSocket support for real-time chat
    location /ws {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
```

**Replace `your-domain.com` with your actual domain name, or use your VPS IP address if not using a domain.**

Enable the site:

```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/crypto-airdrop /etc/nginx/sites-enabled/

# Remove default site
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
sudo nginx -t

# Start Nginx
sudo systemctl start nginx
sudo systemctl enable nginx
```

### Step 10: Configure Firewall

```bash
# Enable UFW firewall
sudo ufw --force enable

# Allow SSH
sudo ufw allow ssh

# Allow HTTP and HTTPS
sudo ufw allow 'Nginx Full'

# Allow specific ports
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Check firewall status
sudo ufw status
```

### Step 11: Install SSL Certificate (Recommended)

If you have a domain name:

```bash
# Install SSL certificate
sudo certbot --nginx -d your-domain.com -d www.your-domain.com --non-interactive --agree-tos --email your-email@example.com

# Test automatic renewal
sudo certbot renew --dry-run
```

### Step 12: Create File Upload Directory

```bash
# Create upload directory with proper permissions
mkdir -p /var/www/crypto-airdrop/public/uploads/images
chmod -R 755 /var/www/crypto-airdrop/public/uploads
```

## Post-Installation Steps

### Default Login Credentials

After installation, you can log in with these default accounts:

- **Admin Account:**
  - Username: `admin`
  - Password: `admin123`

- **Demo Account:**
  - Username: `demo`
  - Password: `demo123`

**⚠️ SECURITY WARNING: Change these passwords immediately after first login!**

### Access Your Application

- **With Domain:** `https://your-domain.com` (if SSL enabled) or `http://your-domain.com`
- **With IP:** `http://your-vps-ip-address`

### Verify Installation

Check if everything is running correctly:

```bash
# Check application status
pm2 status

# Check application logs
pm2 logs crypto-airdrop-platform

# Check Nginx status
sudo systemctl status nginx

# Check PostgreSQL status
sudo systemctl status postgresql

# Test database connection
PGPASSWORD='your-database-password' psql -U airdrop_user -h localhost -d crypto_airdrop_db -c "SELECT COUNT(*) FROM users;"
```

## Maintenance and Management

### Useful Commands

```bash
# View application logs
pm2 logs crypto-airdrop-platform

# Restart application
pm2 restart crypto-airdrop-platform

# Stop application
pm2 stop crypto-airdrop-platform

# View system resources
pm2 monit

# Restart Nginx
sudo systemctl restart nginx

# View Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Update Application

To update your application with new code:

```bash
cd /var/www/crypto-airdrop
git pull
npm install
npm run build
pm2 restart crypto-airdrop-platform
```

### Database Backup

Create a backup script:

```bash
# Create backup directory
mkdir -p /opt/backups

# Create backup script
sudo tee /opt/backup.sh << EOF
#!/bin/bash
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/backups"
mkdir -p \$BACKUP_DIR
PGPASSWORD='your-database-password' pg_dump -U airdrop_user -h localhost crypto_airdrop_db > \$BACKUP_DIR/backup_\$DATE.sql
find \$BACKUP_DIR -name "backup_*.sql" -mtime +7 -delete
echo "Backup completed: \$DATE"
EOF

# Make it executable
sudo chmod +x /opt/backup.sh

# Test backup
sudo /opt/backup.sh

# Schedule daily backups at 2 AM
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/backup.sh") | crontab -
```

## Troubleshooting

### Application Won't Start

```bash
# Check detailed logs
pm2 logs crypto-airdrop-platform --lines 50

# Check if port is in use
sudo lsof -i :5000

# Restart services
sudo systemctl restart postgresql
pm2 restart crypto-airdrop-platform
```

### Database Connection Issues

```bash
# Test database connection
sudo -u postgres psql -d crypto_airdrop_db

# Check PostgreSQL status
sudo systemctl status postgresql

# View PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-*-main.log
```

### Nginx Issues

```bash
# Test Nginx configuration
sudo nginx -t

# Check Nginx logs
sudo tail -f /var/log/nginx/error.log

# Restart Nginx
sudo systemctl restart nginx
```

### SSL Certificate Issues

```bash
# Renew certificate manually
sudo certbot renew

# Check certificate status
sudo certbot certificates

# Test SSL configuration
curl -I https://your-domain.com
```

### File Upload Issues

```bash
# Check upload directory permissions
ls -la /var/www/crypto-airdrop/public/uploads/

# Fix permissions if needed
sudo chown -R www-data:www-data /var/www/crypto-airdrop/public/uploads/
sudo chmod -R 755 /var/www/crypto-airdrop/public/uploads/
```

## Security Best Practices

1. **Change Default Passwords:** Immediately change the default admin and demo passwords
2. **Database Security:** Use strong database passwords and limit access
3. **Regular Updates:** Keep your system and application updated
4. **Firewall:** Only open necessary ports
5. **SSL/TLS:** Always use HTTPS in production
6. **Backups:** Maintain regular database and application backups
7. **Monitoring:** Set up log monitoring and alerts

## Platform Features

Your deployed platform includes:

- **User Authentication:** Registration, login, Web3 wallet integration
- **Role Management:** Admin, Creator, and Regular user roles
- **Airdrop Management:** Create, edit, and view detailed airdrop information
- **Real-time Chat:** WebSocket-powered community chat system
- **Crypto Price Tracking:** Live cryptocurrency price data
- **Creator Applications:** System for users to apply for creator privileges
- **Newsletter System:** Email subscription management
- **Admin Dashboard:** Complete platform administration tools
- **Mobile Responsive:** Optimized for all device types

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review application logs: `pm2 logs crypto-airdrop-platform`
3. Verify all services are running: `sudo systemctl status nginx postgresql`
4. Ensure database connectivity is working
5. Check file permissions for uploads directory

## Automated Installation Script

For a completely automated installation, save the following as `deploy.sh`:

```bash
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_warning "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Get user input
echo "=== Crypto Airdrop Platform VPS Deployment ==="
echo
read -p "Enter your domain name (or press Enter to use IP): " DOMAIN_NAME
read -p "Enter your email for SSL (required if using domain): " EMAIL
read -p "Enter PostgreSQL password (or press Enter to auto-generate): " DB_PASSWORD
read -p "Enter Git repository URL: " REPO_URL

# Generate password if not provided
if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(openssl rand -base64 32)
    print_status "Generated database password: $DB_PASSWORD"
fi

print_status "Starting VPS deployment..."

# Update system
print_status "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install Node.js 20
print_status "Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install required packages
print_status "Installing required packages..."
sudo apt install -y postgresql postgresql-contrib nginx git ufw certbot python3-certbot-nginx

# Install PM2
print_status "Installing PM2..."
sudo npm install -g pm2

# Configure PostgreSQL
print_status "Configuring PostgreSQL..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

sudo -u postgres psql << EOF
CREATE DATABASE crypto_airdrop_db;
CREATE USER airdrop_user WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE crypto_airdrop_db TO airdrop_user;
ALTER USER airdrop_user CREATEDB;
\q
EOF

# Clone and setup application
print_status "Setting up application..."
sudo mkdir -p /var/www
cd /var/www
sudo git clone "$REPO_URL" crypto-airdrop
cd crypto-airdrop
sudo chown -R $USER:$USER /var/www/crypto-airdrop

# Install dependencies
npm install

# Create environment file
cat > .env.production << EOF
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://airdrop_user:$DB_PASSWORD@localhost:5432/crypto_airdrop_db
SESSION_SECRET=$(openssl rand -base64 32)
EOF

# Setup database
print_status "Setting up database..."
npm run db:push
npm run db:seed

# Build application
print_status "Building application..."
npm run build

# Setup PM2
print_status "Configuring PM2..."
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
      PORT: 5000
    },
    env_file: '.env.production'
  }]
}
EOF

pm2 start ecosystem.config.js --env production
pm2 save
pm2 startup
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp $HOME

# Configure Nginx
print_status "Configuring Nginx..."
NGINX_CONF="/etc/nginx/sites-available/crypto-airdrop"
sudo tee $NGINX_CONF << EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME:-_};

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
    }
}
EOF

sudo ln -s $NGINX_CONF /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl start nginx
sudo systemctl enable nginx

# Configure firewall
print_status "Configuring firewall..."
sudo ufw --force enable
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'

# Create upload directory
mkdir -p public/uploads/images
chmod -R 755 public/uploads

# Install SSL if domain provided
if [ -n "$DOMAIN_NAME" ] && [ -n "$EMAIL" ]; then
    print_status "Installing SSL certificate..."
    sudo certbot --nginx -d "$DOMAIN_NAME" -d "www.$DOMAIN_NAME" --non-interactive --agree-tos --email "$EMAIL"
fi

# Setup backup
print_status "Setting up backup system..."
sudo mkdir -p /opt/backups
sudo tee /opt/backup.sh << EOF
#!/bin/bash
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/backups"
mkdir -p \$BACKUP_DIR
PGPASSWORD='$DB_PASSWORD' pg_dump -U airdrop_user -h localhost crypto_airdrop_db > \$BACKUP_DIR/backup_\$DATE.sql
find \$BACKUP_DIR -name "backup_*.sql" -mtime +7 -delete
echo "Backup completed: \$DATE"
EOF

sudo chmod +x /opt/backup.sh
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/backup.sh") | crontab -

print_success "=== DEPLOYMENT COMPLETED ==="
echo
print_status "Application Details:"
echo "• Application URL: http://${DOMAIN_NAME:-$(curl -s ifconfig.me)}"
echo "• Database: crypto_airdrop_db"
echo "• Database User: airdrop_user" 
echo "• Database Password: $DB_PASSWORD"
echo
print_status "Default Login Credentials:"
echo "• Admin User: admin / admin123"
echo "• Demo User: demo / demo123"
echo
print_warning "IMPORTANT SECURITY NOTES:"
echo "• Change default passwords immediately after login"
echo "• Database password saved in: /var/www/crypto-airdrop/.env.production"
echo "• Keep your environment file secure"
echo
print_status "Management Commands:"
echo "• View logs: pm2 logs crypto-airdrop-platform"
echo "• Restart app: pm2 restart crypto-airdrop-platform"
echo "• View status: pm2 status"
echo

if [ -n "$DOMAIN_NAME" ] && [ -n "$EMAIL" ]; then
    print_success "SSL certificate installed! Your site is accessible at: https://$DOMAIN_NAME"
else
    print_status "To add SSL later, run: sudo certbot --nginx"
fi

print_success "Setup completed successfully!"
```

Make the script executable and run it:

```bash
chmod +x deploy.sh
./deploy.sh
```

This automated script will handle the entire deployment process for you.