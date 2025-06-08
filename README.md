# Crypto Airdrop Platform

A comprehensive crypto learning and engagement platform featuring user management, airdrop listings, real-time chat, and role-based access controls.

## Features

- **User Authentication** - Registration, login, Web3 wallet integration
- **Airdrop Management** - Create, view, and manage crypto airdrop tutorials
- **Real-time Chat** - WebSocket-powered community discussions
- **Crypto Tracker** - Live cryptocurrency price feeds
- **Admin Dashboard** - User management and content moderation
- **Creator System** - Application process for content creators
- **Newsletter** - Email subscription management
- **Mobile Responsive** - Optimized for all devices

## Tech Stack

- **Frontend:** React, TypeScript, Tailwind CSS, shadcn/ui
- **Backend:** Node.js, Express, TypeScript
- **Database:** PostgreSQL with Drizzle ORM
- **Real-time:** WebSockets for chat
- **Authentication:** Session-based + Web3 wallet support
- **Process Management:** PM2
- **Reverse Proxy:** Nginx

## Quick Deploy

### One-Command Installation (Recommended)

**For Regular Users with Sudo:**
```bash
curl -fsSL https://raw.githubusercontent.com/your-username/crypto-airdrop-platform/main/install-vps.sh | bash
```

**For Root Users (Enhanced Security):**
```bash
curl -fsSL https://raw.githubusercontent.com/your-username/crypto-airdrop-platform/main/install-vps-root.sh | bash
```

Both scripts handle:
- PostgreSQL database setup (eliminates common connection errors)
- Node.js 20 installation
- Nginx configuration with SSL support
- PM2 process management
- Firewall configuration
- Automated backup system

Root installation additionally includes:
- Dedicated application user creation
- Enhanced security hardening
- Fail2ban intrusion prevention
- Rate limiting and security headers

### Manual Installation

For step-by-step instructions, see [VPS_SETUP_GUIDE.md](VPS_SETUP_GUIDE.md)

For troubleshooting PostgreSQL and deployment issues, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

For root user installation with enhanced security, see [ROOT_USER_GUIDE.md](ROOT_USER_GUIDE.md)

## Development

### Prerequisites
- Node.js 20+
- PostgreSQL
- Git

### Local Setup
```bash
# Clone repository
git clone https://github.com/your-username/crypto-airdrop-platform.git
cd crypto-airdrop-platform

# Install dependencies
npm install

# Setup database
npm run db:push
npm run db:seed

# Start development server
npm run dev
```

The application will be available at `http://localhost:5000`

### Default Credentials
- **Admin:** `admin` / `admin123`
- **Demo:** `demo` / `demo123`

## Production Deployment

### Requirements
- Ubuntu 20.04+ or Debian 11+ VPS
- 1GB+ RAM, 20GB+ storage
- Domain name (optional but recommended)

### Environment Variables
```env
NODE_ENV=production
DATABASE_URL=postgresql://user:password@localhost:5432/database
SESSION_SECRET=your_secure_session_secret
PORT=5000
```

### Management Commands
```bash
# Application status
pm2 status

# View logs
pm2 logs crypto-airdrop

# Restart application
pm2 restart crypto-airdrop

# Database backup
sudo /opt/crypto-backups/backup.sh

# Update application
cd /var/www/crypto-airdrop && git pull && npm install && npm run build && pm2 restart crypto-airdrop
```

## Security Features

- SSL/TLS encryption
- Firewall protection
- Security headers
- Password hashing
- Session management
- Input validation
- SQL injection prevention
- XSS protection

## API Endpoints

### Authentication
- `POST /api/register` - User registration
- `POST /api/login` - User login
- `POST /api/logout` - User logout
- `GET /api/user` - Get current user

### Airdrops
- `GET /api/airdrops` - List airdrops
- `GET /api/airdrops/featured` - Featured airdrops
- `GET /api/airdrop/:id` - Get airdrop details
- `POST /api/airdrops` - Create airdrop (admin/creator)

### Categories
- `GET /api/categories` - List categories
- `POST /api/categories` - Create category (admin)

### Crypto
- `GET /api/crypto/prices` - Live crypto prices

### Chat
- `WebSocket /ws` - Real-time chat

## License

MIT License - see LICENSE file for details

## Support

For deployment issues, check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

For detailed setup instructions, see [VPS_SETUP_GUIDE.md](VPS_SETUP_GUIDE.md)

---

**Ready for production deployment with automated setup scripts**