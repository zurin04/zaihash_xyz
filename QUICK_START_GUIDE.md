# Quick Start VPS Deployment Guide

Deploy your crypto airdrop platform in under 10 minutes with this automated setup.

## Prerequisites

- Ubuntu 20.04 or 22.04 VPS
- SSH access with sudo privileges
- Domain name (optional)
- Email address (for SSL)

## One-Command Installation

```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/crypto-airdrop-platform/main/deploy.sh | bash
```

## Manual Installation

If you prefer to download and review the script first:

```bash
# Download the script
wget https://raw.githubusercontent.com/yourusername/crypto-airdrop-platform/main/deploy.sh

# Make it executable
chmod +x deploy.sh

# Run the installation
./deploy.sh
```

## What Gets Installed

- Node.js 20 runtime environment
- PostgreSQL database with crypto_airdrop_db
- Nginx web server with proxy configuration
- PM2 process manager for application lifecycle
- UFW firewall with secure defaults
- SSL certificate (if domain provided)
- Automated backup system

## Default Credentials

After installation, access your platform with:

**Admin Account:**
- Username: `admin`
- Password: `admin123`

**Demo Account:**
- Username: `demo`
- Password: `demo123`

Change these passwords immediately after first login.

## Post-Installation

### Access Your Platform
- With domain: `https://yourdomain.com` or `http://yourdomain.com`
- With IP: `http://your-vps-ip`

### Management Commands
```bash
# View application status
pm2 status

# View application logs
pm2 logs crypto-airdrop-platform

# Restart application
pm2 restart crypto-airdrop-platform

# Update application
sudo /opt/crypto-airdrop/update.sh

# Manual backup
sudo /opt/crypto-airdrop/backup.sh
```

### Troubleshooting

**Application not starting:**
```bash
pm2 logs crypto-airdrop-platform --lines 50
```

**Database connection issues:**
```bash
sudo systemctl status postgresql
```

**Web server problems:**
```bash
sudo nginx -t
sudo systemctl status nginx
```

## Features Available

Your deployed platform includes:

- User registration and authentication
- Web3 wallet integration (MetaMask, WalletConnect)
- Admin dashboard for platform management
- Creator application system
- Real-time community chat
- Airdrop creation and management
- Cryptocurrency price tracking
- Newsletter subscription system
- Mobile-responsive design

## Security Features

- UFW firewall protection
- SSL/TLS encryption (if domain configured)
- Secure session management
- Input validation and sanitization
- CSRF protection
- Rate limiting on API endpoints

## Backup System

Automated daily backups at 2 AM include:
- Complete database dump
- Application files (excluding node_modules)
- 7-day retention policy

Backup location: `/opt/crypto-airdrop/backups`

## Support

For issues during deployment:
1. Check the installation logs for error messages
2. Verify all services are running: `sudo systemctl status nginx postgresql`
3. Ensure firewall allows HTTP/HTTPS traffic
4. Confirm database connectivity with provided credentials

## Next Steps

1. Access your platform using the provided URL
2. Log in with admin credentials
3. Change default passwords in user settings
4. Configure site settings through admin panel
5. Create your first airdrop listing
6. Invite users to join your platform

Your crypto airdrop platform is now ready for production use.