# Troubleshooting Guide

This guide addresses common issues during VPS deployment and provides solutions for PostgreSQL, application, and server configuration problems.

## PostgreSQL Issues

### Database Connection Failed

**Symptoms:**
- "database connection failed" error
- "ECONNREFUSED" errors
- Authentication failures

**Solutions:**

1. **Check PostgreSQL Status**
```bash
sudo systemctl status postgresql
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

2. **Verify Database and User**
```bash
sudo -u postgres psql -l | grep crypto_airdrop_db
sudo -u postgres psql -c "\du" | grep airdrop_user
```

3. **Reset Database Setup**
```bash
sudo -u postgres psql << 'EOF'
DROP DATABASE IF EXISTS crypto_airdrop_db;
DROP USER IF EXISTS airdrop_user;
CREATE DATABASE crypto_airdrop_db;
CREATE USER airdrop_user WITH ENCRYPTED PASSWORD 'YourPassword';
GRANT ALL PRIVILEGES ON DATABASE crypto_airdrop_db TO airdrop_user;
ALTER USER airdrop_user CREATEDB;
EOF
```

4. **Test Connection**
```bash
PGPASSWORD='YourPassword' psql -U airdrop_user -h localhost crypto_airdrop_db -c "SELECT 1;"
```

### PostgreSQL Won't Start

**Check logs:**
```bash
sudo tail -f /var/log/postgresql/postgresql-*-main.log
```

**Common fixes:**
```bash
# Fix permissions
sudo chown -R postgres:postgres /var/lib/postgresql/
sudo chmod 700 /var/lib/postgresql/*/main

# Restart service
sudo systemctl restart postgresql
```

## Application Issues

### App Won't Start

**Check PM2 status:**
```bash
pm2 status
pm2 logs crypto-airdrop --lines 50
```

**Common fixes:**

1. **Environment file issues:**
```bash
cd /var/www/crypto-airdrop
cat .env.production  # Check if file exists and has correct format
chmod 600 .env.production
```

2. **Dependencies missing:**
```bash
cd /var/www/crypto-airdrop
npm install
npm run build
pm2 restart crypto-airdrop
```

3. **Port conflicts:**
```bash
sudo lsof -i :5000  # Check if port is in use
sudo kill -9 PID_NUMBER  # Kill conflicting process
```

### Database Schema Errors

**Symptoms:**
- "relation does not exist" errors
- Missing table errors

**Solutions:**

1. **Reinitialize schema:**
```bash
cd /var/www/crypto-airdrop
npm run db:push
npm run db:seed
```

2. **Check database tables:**
```bash
PGPASSWORD='YourPassword' psql -U airdrop_user -h localhost crypto_airdrop_db -c "\dt"
```

### Memory Issues

**Check system resources:**
```bash
free -h
df -h
pm2 monit
```

**Increase memory limits:**
```javascript
// In ecosystem.config.js
max_memory_restart: '2G'  // Increase from 1G
```

## Web Server Issues

### Nginx Configuration Errors

**Test configuration:**
```bash
sudo nginx -t
```

**Check logs:**
```bash
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

**Common fixes:**

1. **Syntax errors in config:**
```bash
sudo nano /etc/nginx/sites-available/crypto-airdrop
sudo nginx -t  # Test after changes
sudo systemctl reload nginx
```

2. **Permission issues:**
```bash
sudo chown -R www-data:www-data /var/www/crypto-airdrop/public/
sudo chmod -R 755 /var/www/crypto-airdrop/public/
```

### SSL Certificate Issues

**Check certificate status:**
```bash
sudo certbot certificates
```

**Renew certificate:**
```bash
sudo certbot renew --dry-run
sudo certbot renew
```

**Fix certificate problems:**
```bash
sudo certbot delete  # Remove existing certificate
sudo certbot --nginx -d yourdomain.com  # Reinstall
```

## Network and Firewall Issues

### Can't Access Website

**Check firewall:**
```bash
sudo ufw status
sudo ufw allow 'Nginx Full'
sudo ufw allow ssh
```

**Check if services are listening:**
```bash
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443
sudo netstat -tlnp | grep :5000
```

### WebSocket Connection Failed

**Check Nginx WebSocket config:**
```bash
# Ensure /ws location is properly configured
sudo nano /etc/nginx/sites-available/crypto-airdrop
```

**Test WebSocket endpoint:**
```bash
curl -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: test" \
  -H "Sec-WebSocket-Version: 13" \
  http://localhost:5000/ws
```

## File Upload Issues

### Upload Directory Problems

**Create and fix permissions:**
```bash
cd /var/www/crypto-airdrop
mkdir -p public/uploads/images public/uploads/avatars
sudo chown -R $USER:www-data public/uploads/
sudo chmod -R 775 public/uploads/
```

**Check Nginx static file serving:**
```nginx
# In /etc/nginx/sites-available/crypto-airdrop
location /uploads/ {
    alias /var/www/crypto-airdrop/public/uploads/;
    expires 30d;
}
```

## Performance Issues

### Slow Database Queries

**Check database performance:**
```bash
PGPASSWORD='YourPassword' psql -U airdrop_user -h localhost crypto_airdrop_db -c "
SELECT schemaname,tablename,attname,n_distinct,correlation 
FROM pg_stats 
WHERE tablename IN ('users','airdrops','categories');"
```

**Optimize database:**
```bash
PGPASSWORD='YourPassword' psql -U airdrop_user -h localhost crypto_airdrop_db -c "VACUUM ANALYZE;"
```

### High Memory Usage

**Monitor resources:**
```bash
pm2 monit
htop
```

**Restart application:**
```bash
pm2 restart crypto-airdrop
```

## Backup and Recovery

### Restore from Backup

**Database restore:**
```bash
PGPASSWORD='YourPassword' psql -U airdrop_user -h localhost crypto_airdrop_db < backup.sql
```

**Application restore:**
```bash
cd /var/www
sudo rm -rf crypto-airdrop
sudo tar -xzf app_backup_DATE.tar.gz
cd crypto-airdrop
npm install
pm2 restart crypto-airdrop
```

## Security Issues

### Unauthorized Access

**Check logs for suspicious activity:**
```bash
sudo tail -f /var/log/nginx/access.log | grep -E "(POST|PUT|DELETE)"
pm2 logs crypto-airdrop | grep -i error
```

**Update passwords:**
```bash
# Change database password
sudo -u postgres psql -c "ALTER USER airdrop_user PASSWORD 'NewSecurePassword';"

# Update .env.production with new password
cd /var/www/crypto-airdrop
nano .env.production
pm2 restart crypto-airdrop
```

## Complete System Reset

If all else fails, clean reinstall:

```bash
# Stop all services
pm2 stop all
sudo systemctl stop nginx postgresql

# Remove application
sudo rm -rf /var/www/crypto-airdrop

# Reset database
sudo -u postgres psql -c "DROP DATABASE IF EXISTS crypto_airdrop_db;"
sudo -u postgres psql -c "DROP USER IF EXISTS airdrop_user;"

# Run installation script again
curl -fsSL https://raw.githubusercontent.com/your-repo/crypto-airdrop-platform/main/install-vps.sh | bash
```

## Getting Help

1. **Check application logs:** `pm2 logs crypto-airdrop --lines 100`
2. **Check system logs:** `sudo journalctl -u nginx -u postgresql --since "1 hour ago"`
3. **Verify all services:** `sudo systemctl status nginx postgresql`
4. **Test database connection:** Follow PostgreSQL troubleshooting steps
5. **Check network connectivity:** Ensure firewall allows traffic

## Prevention Tips

- Keep system updated: `sudo apt update && sudo apt upgrade`
- Monitor disk space: `df -h`
- Regular backups: Automated daily backups are configured
- Monitor logs: Set up log rotation and monitoring
- Security updates: Enable automatic security updates