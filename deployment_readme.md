# Django EC2 Advanced Deployment Script

## Overview

This comprehensive deployment script automates Django application deployment on EC2 with advanced DevOps features including health monitoring, auto-scaling, backup systems, and automatic rollback capabilities.

## 🚀 Features

### Core Deployment Features
- ✅ **Automated Django Setup** - Complete Django app deployment with Gunicorn and Nginx
- ✅ **PostgreSQL Configuration** - Automated database setup and configuration
- ✅ **SSL Certificate Management** - Automatic Let's Encrypt SSL certificates
- ✅ **React Frontend Support** - Optional React frontend deployment with API proxy
- ✅ **Environment Variable Management** - Secure environment configuration

### Advanced DevOps Features
- 🔍 **Health Monitoring** - Automated health checks with email alerts
- 📧 **Email Notifications** - Real-time alerts for deployment and system issues
- 📊 **Performance Monitoring** - CPU, memory, and load monitoring with thresholds
- 🔄 **Auto-Scaling** - Dynamic worker scaling based on system metrics
- 💾 **Automated Backups** - Daily database backups with rotation policy
- 🔙 **Automatic Rollback** - Deployment failure detection and automatic recovery
- 📈 **System Metrics** - Comprehensive performance tracking

## 📋 Prerequisites

### System Requirements
- Ubuntu 20.04+ EC2 instance
- Minimum 2GB RAM (4GB recommended)
- 20GB+ storage space
- Domain name pointed to your EC2 instance

### Required Files in Your Project
- `requirements.txt` - Python dependencies
- `manage.py` - Django management script
- Proper Django project structure
- Environment variables (via script input or .env file)

### For Frontend Deployment (Optional)
- React project with `dist/` folder (run `npm run build` first)
- Frontend domain name

## 🛠️ Installation & Usage

### 1. Initial Setup

```bash
# Download the script
wget https://your-script-location/django_deploy.sh

# Make executable
chmod +x django_deploy.sh

# Run from your home directory (where your Django project is located)
cd ~
./django_deploy.sh
```

### 2. Configuration During Installation

The script will prompt you for:

#### Required Information
- **App Name**: Used for service naming (e.g., `my-app`)
- **Backend Domain**: Your API domain (e.g., `api.example.com`)
- **Project Directory**: Django project folder name
- **Django Module**: Django project module for WSGI
- **Database Name**: PostgreSQL database name
- **Database Password**: PostgreSQL password

#### Environment Variables
Choose one option:
1. **Paste complete .env file** (recommended)
2. **Manual entry** (basic setup only)

#### Frontend (Optional)
- **Frontend Directory**: React project folder
- **Frontend Domain**: Frontend domain (e.g., `app.example.com`)
- **Frontend App Name**: Nginx configuration name

## 🎯 Endpoints & Access Points

### Backend Endpoints

| Endpoint | Purpose | Example URL |
|----------|---------|-------------|
| `/` | Main application | `https://api.example.com/` |
| `/admin/` | Django admin panel | `https://api.example.com/admin/` |
| `/api/` | API endpoints | `https://api.example.com/api/` |
| `/yele-docs` | API documentation (Swagger) | `https://api.example.com/yele-docs` |
| `/health/` | Health check endpoint | `https://api.example.com/health/` |
| `/static/` | Static files | `https://api.example.com/static/` |
| `/media/` | Media files | `https://api.example.com/media/` |

### Frontend Endpoints (if deployed)

| Endpoint | Purpose | Example URL |
|----------|---------|-------------|
| `/` | React application | `https://app.example.com/` |
| `/admin/` | Proxied admin panel | `https://app.example.com/admin/` |
| `/api/` | Proxied API | `https://app.example.com/api/` |
| `/yele-docs` | Proxied docs | `https://app.example.com/yele-docs` |
| `/health/` | Proxied health check | `https://app.example.com/health/` |

## 🔧 Management Commands

### Application Management Utility

```bash
# Navigate to your project
cd /path/to/your/project

# Use the management utility
./manage_app.sh [command]
```

#### Available Commands

| Command | Description | Example |
|---------|-------------|---------|
| `status` | Show service status | `./manage_app.sh status` |
| `restart` | Restart all services | `./manage_app.sh restart` |
| `logs` | Show recent logs | `./manage_app.sh logs` |
| `health` | Run health check | `./manage_app.sh health` |
| `backup` | Create manual backup | `./manage_app.sh backup` |
| `scale [num]` | Set worker count | `./manage_app.sh scale 5` |
| `rollback [id]` | Rollback to snapshot | `./manage_app.sh rollback 20240815_143022` |
| `snapshots` | List snapshots | `./manage_app.sh snapshots` |
| `monitor` | Performance metrics | `./manage_app.sh monitor` |

### Direct System Commands

```bash
# Service management
sudo systemctl status gunicorn-YOUR_APP.service
sudo systemctl restart gunicorn-YOUR_APP.service
sudo systemctl status nginx
sudo systemctl restart nginx

# Log monitoring
sudo journalctl -u gunicorn-YOUR_APP.service -f
sudo tail -f /var/log/nginx/YOUR_APP.error.log
./monitor_logs.sh  # Colored log monitoring

# Deployment updates
./deploy_update.sh  # Update with rollback support
```

## 📊 Monitoring & Alerting

### Health Monitoring

**Frequency**: Every 5 minutes  
**Email**: chris@yelegroup.africa

**Monitored Components**:
- HTTP response status
- Gunicorn service status
- Nginx service status
- PostgreSQL service status
- Disk space (>90% triggers alert)
- Memory usage (>90% triggers alert)

**Manual Health Check**:
```bash
/opt/monitoring/YOUR_APP/health_check.py
```

### Performance Monitoring

**Frequency**: Every 10 minutes  
**Email**: chris@yelegroup.africa

**Thresholds**:
- CPU usage: >80%
- Memory usage: >80%
- Disk usage: >85%
- Load average: >4.0

**Manual Performance Check**:
```bash
/opt/monitoring/YOUR_APP/performance_monitor.py
```

### Auto-Scaling

**Frequency**: Every 15 minutes  
**Worker Range**: 2-8 workers

**Scale Up Triggers**:
- CPU usage >70%
- Memory usage >70%

**Scale Down Triggers**:
- CPU usage <30%
- Memory usage <30%

**Manual Scaling**:
```bash
./manage_app.sh scale 6  # Set to 6 workers
```

## 💾 Backup System

### Automated Database Backups

**Schedule**: Daily at 2:00 AM  
**Retention**: 7 days  
**Location**: `/opt/backups/YOUR_APP/database/`  
**Format**: Compressed SQL dumps (`.sql.gz`)

**Manual Backup**:
```bash
/opt/monitoring/YOUR_APP/db_backup.sh
```

**Backup Files**:
```bash
# List backups
ls -la /opt/backups/YOUR_APP/database/

# Example backup file
YOUR_DB_20240815_020001.sql.gz
```

## 🔙 Rollback System

### Automatic Rollback

**Trigger**: Deployment health check failure  
**Frequency**: Every 5 minutes after deployment  
**Email**: chris@yelegroup.africa

**What's Included in Snapshots**:
- Database state
- Git commit hash
- Gunicorn configuration
- Environment variables
- Application configuration

### Manual Rollback

```bash
# List available snapshots
./manage_app.sh snapshots

# Rollback to specific snapshot
./manage_app.sh rollback 20240815_143022

# Create manual snapshot
/opt/monitoring/YOUR_APP/rollback_manager.py snapshot
```

## 📧 Email Notifications

All notifications are sent to: **chris@yelegroup.africa**

### Notification Types

| Event | Frequency | Content |
|-------|-----------|---------|
| Deployment Success | Per deployment | Confirmation with timestamp |
| Deployment Failure | Per failure | Error details and cleanup status |
| Health Check Failure | Every 5 min (if issues) | Failed components and metrics |
| Performance Alert | Every 10 min (if thresholds exceeded) | Resource usage details |
| Auto-Scaling Event | Per scaling action | Worker count changes and metrics |
| Backup Success | Weekly (Mondays) | Backup completion confirmation |
| Backup Failure | Per failure | Error details |
| Rollback Event | Per rollback | Rollback details and status |

### Email Testing

```bash
# Test email functionality
echo "Test message" | mail -s "Test Subject" chris@yelegroup.africa

# Check mail logs
sudo tail -f /var/log/mail.log
```

## 📁 File Structure

### Project Files Created
```
/path/to/your/project/
├── gunicorn.conf.py          # Gunicorn configuration
├── .env                      # Environment variables
├── deploy_update.sh          # Deployment update script
├── monitor_logs.sh           # Log monitoring script
├── manage_app.sh             # App management utility
└── venv/                     # Python virtual environment
```

### System Files Created
```
/etc/systemd/system/
└── gunicorn-YOUR_APP.service # Systemd service file

/etc/nginx/sites-available/
├── YOUR_APP                  # Backend nginx config
└── FRONTEND_APP             # Frontend nginx config (if deployed)

/opt/monitoring/YOUR_APP/
├── health_check.py          # Health monitoring script
├── performance_monitor.py   # Performance monitoring script
├── auto_scale.py           # Auto-scaling script
├── rollback_manager.py     # Rollback management script
├── db_backup.sh            # Database backup script
└── rollback_snapshots/     # Rollback snapshots directory

/opt/backups/YOUR_APP/
└── database/               # Database backup files

/var/log/
├── gunicorn/
│   ├── YOUR_APP-access.log # Gunicorn access logs
│   └── YOUR_APP-error.log  # Gunicorn error logs
└── nginx/
    ├── YOUR_APP.access.log # Nginx access logs
    └── YOUR_APP.error.log  # Nginx error logs
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Service Not Starting
```bash
# Check service status
./manage_app.sh status

# View detailed logs
./manage_app.sh logs

# Check configuration
sudo nginx -t
```

#### 2. Health Check Failures
```bash
# Run manual health check
./manage_app.sh health

# Check individual components
sudo systemctl status gunicorn-YOUR_APP.service
sudo systemctl status nginx
sudo systemctl status postgresql
```

#### 3. Email Notifications Not Working
```bash
# Test email functionality
echo "Test" | mail -s "Test" chris@yelegroup.africa

# Install mail if missing
sudo apt install mailutils

# Check mail logs
sudo tail -f /var/log/mail.log
```

#### 4. Auto-Scaling Issues
```bash
# Check auto-scaling logs
sudo grep "AUTO_SCALE" /var/log/syslog

# Manual scaling test
./manage_app.sh scale 4

# Check current worker count
ps aux | grep gunicorn | grep YOUR_APP
```

#### 5. Backup Failures
```bash
# Test manual backup
./manage_app.sh backup

# Check backup directory
ls -la /opt/backups/YOUR_APP/database/

# Test database connection
psql -h localhost -U postgres -d YOUR_DB_NAME
```

### Log Locations

| Service | Access Logs | Error Logs |
|---------|-------------|------------|
| Gunicorn | `/var/log/gunicorn/YOUR_APP-access.log` | `/var/log/gunicorn/YOUR_APP-error.log` |
| Nginx | `/var/log/nginx/YOUR_APP.access.log` | `/var/log/nginx/YOUR_APP.error.log` |
| System | `/var/log/syslog` | `/var/log/syslog` |
| Cron Jobs | `/var/log/cron.log` | `/var/log/cron.log` |

### Performance Monitoring

```bash
# Real-time monitoring
htop                    # Process monitor
iftop                  # Network monitor
sudo iotop             # Disk I/O monitor

# System metrics
./manage_app.sh monitor # Quick overview
df -h                  # Disk usage
free -h                # Memory usage
uptime                 # Load average
```

## 🔐 Security Features

### Firewall Configuration
- SSH (port 22) - Allow
- HTTP (port 80) - Allow  
- HTTPS (port 443) - Allow
- All other ports - Deny

### SSL/TLS
- Automatic Let's Encrypt certificates
- Auto-renewal configured
- Force HTTPS redirects

### File Permissions
- Application files: `ubuntu:ubuntu`
- Web files: `www-data:www-data`
- Configuration files: `644` permissions
- Scripts: `755` permissions

### Database Security
- Local connections only
- MD5 authentication
- Strong password enforcement

## 🔄 Deployment Updates

### Automated Updates with Rollback
```bash
# Navigate to project directory
cd /path/to/your/project

# Run update script (includes automatic rollback on failure)
./deploy_update.sh
```

**Update Process**:
1. Creates pre-deployment snapshot
2. Pulls latest code changes
3. Updates dependencies
4. Runs migrations
5. Collects static files
6. Restarts services
7. Performs health check
8. Triggers rollback if health check fails
9. Sends email notification

### Manual Deployment Steps
```bash
cd /path/to/your/project
source venv/bin/activate

# Update code
git pull origin main

# Update dependencies
pip install -r requirements.txt

# Django updates
python manage.py migrate
python manage.py collectstatic --noinput

# Restart services
sudo systemctl restart gunicorn-YOUR_APP.service
sudo systemctl restart nginx
```

## 📱 Frontend Updates (If Deployed)

### React Frontend Updates
```bash
# In your React project directory
npm run build

# Copy to web directory
sudo cp -r dist/* /var/www/YOUR_FRONTEND_DOMAIN/

# Set permissions
sudo chown -R www-data:www-data /var/www/YOUR_FRONTEND_DOMAIN/
```

## 🎛️ Configuration Customization

### Gunicorn Configuration
Edit: `/path/to/your/project/gunicorn.conf.py`

```python
# Worker configuration
workers = 3                    # Number of worker processes
worker_class = "sync"         # Worker class
worker_connections = 1000     # Connections per worker
max_requests = 1000          # Requests before worker restart
timeout = 120                # Worker timeout

# Scaling thresholds (in auto_scale.py)
SCALE_UP_CPU = 70           # CPU % to scale up
SCALE_DOWN_CPU = 30         # CPU % to scale down
MIN_WORKERS = 2             # Minimum workers
MAX_WORKERS = 8             # Maximum workers
```

### Monitoring Thresholds
Edit: `/opt/monitoring/YOUR_APP/performance_monitor.py`

```python
# Performance thresholds
CPU_THRESHOLD = 80          # CPU alert threshold
MEMORY_THRESHOLD = 80       # Memory alert threshold
DISK_THRESHOLD = 85         # Disk alert threshold
LOAD_THRESHOLD = 4.0        # Load average threshold
```

### Backup Retention
Edit: `/opt/monitoring/YOUR_APP/db_backup.sh`

```bash
# Change retention period (currently 7 days)
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
```

## 🆘 Emergency Procedures

### Complete Service Restart
```bash
sudo systemctl restart gunicorn-YOUR_APP.service
sudo systemctl restart nginx
sudo systemctl restart postgresql
```

### Emergency Rollback
```bash
# List snapshots
./manage_app.sh snapshots

# Rollback to last known good state
./manage_app.sh rollback SNAPSHOT_ID
```

### Disable Monitoring (Emergency)
```bash
# Disable cron jobs temporarily
crontab -l > /tmp/crontab_backup
crontab -r

# Re-enable later
crontab /tmp/crontab_backup
```

### Database Recovery
```bash
# List backups
ls -la /opt/backups/YOUR_APP/database/

# Restore from backup
gunzip /opt/backups/YOUR_APP/database/BACKUP_FILE.sql.gz
dropdb -h localhost -U postgres YOUR_DB_NAME
createdb -h localhost -U postgres YOUR_DB_NAME
psql -h localhost -U postgres -d YOUR_DB_NAME -f BACKUP_FILE.sql
```

## 📞 Support & Maintenance

### Regular Maintenance Tasks

#### Weekly
- Check backup integrity
- Review performance metrics
- Monitor disk usage
- Update system packages

#### Monthly  
- Review and rotate logs
- Check SSL certificate expiry
- Update dependencies
- Security audit

### Contact Information
- **Email Notifications**: chris@yelegroup.africa
- **System Logs**: Check `/var/log/syslog` for all system events
- **Application Logs**: Use `./manage_app.sh logs` for application-specific logs

---

## 📄 License & Credits

This deployment script automates Django deployment with advanced DevOps features. Customize according to your specific requirements and security policies.

**Created for**: Professional Django deployment automation  
**Maintained by**: DevOps Team  
**Last Updated**: August 2025