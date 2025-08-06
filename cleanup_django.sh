#!/bin/bash

# Django Deployment Cleanup Script
# This script removes everything created by the Django deployment script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

print_header "Django Deployment Cleanup Script"
echo "This script will remove ALL components created by the Django deployment script"
echo ""

print_warning "This will remove:"
print_warning "• All Gunicorn services and configurations"
print_warning "• All Nginx configurations"
print_warning "• All PostgreSQL databases created by the deployment"
print_warning "• All SSL certificates"
print_warning "• All log files"
print_warning "• Python virtual environments in project directories"
print_warning "• Generated deployment files (.env, gunicorn.conf.py, etc.)"
echo ""

read -p "Are you sure you want to proceed? (y/N): " confirm
if [[ $confirm != "y" && $confirm != "Y" ]]; then
    print_status "Cleanup cancelled"
    exit 0
fi

echo ""
read -p "Enter your project directory name (e.g., Eduteka-Backend): " PROJECT_DIR
read -p "Enter your frontend directory name (e.g., eduteka) or press Enter to skip: " FRONTEND_DIR

PROJECT_PATH="/home/ubuntu/$PROJECT_DIR"
if [ -n "$FRONTEND_DIR" ]; then
    FRONTEND_PATH="/home/ubuntu/$FRONTEND_DIR"
fi

print_header "Starting Cleanup Process"

# =============================================================================
# STOP AND REMOVE SERVICES
# =============================================================================

print_status "Stopping and removing all Gunicorn services..."

# Find all gunicorn services
GUNICORN_SERVICES=$(sudo systemctl list-units --type=service | grep gunicorn | awk '{print $1}')

if [ -n "$GUNICORN_SERVICES" ]; then
    for service in $GUNICORN_SERVICES; do
        print_status "Stopping service: $service"
        sudo systemctl stop "$service" 2>/dev/null || true
        sudo systemctl disable "$service" 2>/dev/null || true
    done
fi

# Remove all gunicorn service files
print_status "Removing Gunicorn service files..."
sudo rm -f /etc/systemd/system/gunicorn-*.service
sudo rm -f /etc/tmpfiles.d/gunicorn-*.conf

# =============================================================================
# REMOVE NGINX CONFIGURATIONS
# =============================================================================

print_status "Removing Nginx configurations..."

# Remove all nginx sites that might be deployment-related
sudo rm -f /etc/nginx/sites-available/*-backend
sudo rm -f /etc/nginx/sites-available/*-frontend
sudo rm -f /etc/nginx/sites-available/eduteka*
sudo rm -f /etc/nginx/sites-enabled/*-backend
sudo rm -f /etc/nginx/sites-enabled/*-frontend
sudo rm -f /etc/nginx/sites-enabled/eduteka*

# Restore default if it doesn't exist
if [ ! -f /etc/nginx/sites-available/default ]; then
    print_status "Restoring default Nginx configuration..."
    sudo tee /etc/nginx/sites-available/default > /dev/null << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
    sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
fi

# Test and reload nginx
sudo nginx -t && sudo systemctl reload nginx

# =============================================================================
# REMOVE SSL CERTIFICATES
# =============================================================================

print_status "Removing SSL certificates..."

# List and remove certificates
CERT_DOMAINS=$(sudo certbot certificates 2>/dev/null | grep "Certificate Name" | awk '{print $3}' || true)

if [ -n "$CERT_DOMAINS" ]; then
    for domain in $CERT_DOMAINS; do
        print_status "Removing SSL certificate for: $domain"
        sudo certbot delete --cert-name "$domain" --non-interactive 2>/dev/null || true
    done
fi

# Remove certbot cron jobs
print_status "Removing certbot cron jobs..."
(sudo crontab -l 2>/dev/null | grep -v certbot) | sudo crontab - 2>/dev/null || true

# =============================================================================
# CLEAN UP DATABASES
# =============================================================================

print_header "Database Cleanup"

print_status "Scanning for deployment-created databases..."

# Get list of databases (excluding system databases)
DATABASES=$(sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -v template | grep -v postgres | sed 's/^ *//g' | grep -v '^$' || true)

if [ -n "$DATABASES" ]; then
    echo "Found the following databases:"
    echo "$DATABASES"
    echo ""
    read -p "Do you want to remove specific databases? (y/n): " remove_dbs
    
    if [[ $remove_dbs == "y" || $remove_dbs == "Y" ]]; then
        echo "Enter database names to remove (one per line, press Enter twice when done):"
        DBS_TO_REMOVE=()
        while true; do
            read -p "Database name (or press Enter to finish): " db_name
            if [ -z "$db_name" ]; then
                break
            fi
            DBS_TO_REMOVE+=("$db_name")
        done
        
        for db in "${DBS_TO_REMOVE[@]}"; do
            print_status "Dropping database: $db"
            sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$db\";" 2>/dev/null || print_error "Failed to drop database: $db"
        done
    fi
fi

# =============================================================================
# REMOVE LOG FILES
# =============================================================================

print_status "Removing log files..."

# Remove gunicorn logs
sudo rm -rf /var/log/gunicorn/
sudo rm -f /var/log/nginx/*-backend.*
sudo rm -f /var/log/nginx/*-frontend.*
sudo rm -f /var/log/nginx/eduteka*

# =============================================================================
# REMOVE SOCKET DIRECTORIES
# =============================================================================

print_status "Removing socket directories..."
sudo rm -rf /run/gunicorn

# =============================================================================
# CLEAN UP PROJECT DIRECTORIES
# =============================================================================

print_header "Cleaning Project Directories"

if [ -d "$PROJECT_PATH" ]; then
    print_status "Cleaning backend project directory: $PROJECT_PATH"
    
    # Remove virtual environment
    if [ -d "$PROJECT_PATH/venv" ]; then
        print_status "Removing Python virtual environment..."
        rm -rf "$PROJECT_PATH/venv"
    fi
    
    # Remove generated files
    print_status "Removing generated deployment files..."
    rm -f "$PROJECT_PATH/.env"
    rm -f "$PROJECT_PATH/gunicorn.conf.py"
    rm -f "$PROJECT_PATH/deploy_update.sh"
    rm -f "$PROJECT_PATH/monitor_logs.sh"
    
    # Remove collected static files (optional)
    read -p "Remove collected static files? (y/n): " remove_static
    if [[ $remove_static == "y" || $remove_static == "Y" ]]; then
        rm -rf "$PROJECT_PATH/staticfiles"
        print_status "Removed staticfiles directory"
    fi
    
    # Remove media files (optional)
    read -p "Remove media files? (y/n): " remove_media
    if [[ $remove_media == "y" || $remove_media == "Y" ]]; then
        rm -rf "$PROJECT_PATH/media"
        print_status "Removed media directory"
    fi
else
    print_warning "Backend project directory not found: $PROJECT_PATH"
fi

if [ -n "$FRONTEND_DIR" ] && [ -d "$FRONTEND_PATH" ]; then
    print_status "Frontend directory found: $FRONTEND_PATH"
    print_warning "Frontend source files preserved (only deployment configs removed)"
fi

# =============================================================================
# RELOAD SYSTEMD AND SERVICES
# =============================================================================

print_status "Reloading systemd daemon..."
sudo systemctl daemon-reload

print_status "Restarting services..."
sudo systemctl restart nginx

# =============================================================================
# FIREWALL CLEANUP (OPTIONAL)
# =============================================================================

print_status "Firewall cleanup..."
read -p "Reset firewall rules to default? (y/n): " reset_firewall

if [[ $reset_firewall == "y" || $reset_firewall == "Y" ]]; then
    print_status "Resetting UFW to defaults..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow OpenSSH
    sudo ufw --force enable
fi

# =============================================================================
# PACKAGE CLEANUP (OPTIONAL)
# =============================================================================

print_status "Package cleanup..."
read -p "Remove deployment-specific packages? (y/n): " remove_packages

if [[ $remove_packages == "y" || $remove_packages == "Y" ]]; then
    print_status "Removing deployment packages..."
    sudo apt remove --purge -y certbot python3-certbot-nginx 2>/dev/null || true
    sudo apt autoremove -y 2>/dev/null || true
    print_status "Packages removed"
fi

# =============================================================================
# VERIFICATION
# =============================================================================

print_header "Cleanup Verification"

# Check for remaining services
REMAINING_SERVICES=$(sudo systemctl list-units --type=service | grep gunicorn | wc -l)
if [ "$REMAINING_SERVICES" -eq 0 ]; then
    print_status "✓ All Gunicorn services removed"
else
    print_warning "⚠ Some Gunicorn services may still exist"
fi

# Check nginx config
if sudo nginx -t >/dev/null 2>&1; then
    print_status "✓ Nginx configuration is valid"
else
    print_error "✗ Nginx configuration has issues"
fi

# Check for remaining files
REMAINING_CONFIGS=$(find /etc/nginx/sites-* -name "*backend*" -o -name "*frontend*" -o -name "eduteka*" 2>/dev/null | wc -l)
if [ "$REMAINING_CONFIGS" -eq 0 ]; then
    print_status "✓ All deployment nginx configs removed"
else
    print_warning "⚠ Some nginx configs may remain"
fi

# =============================================================================
# COMPLETION SUMMARY
# =============================================================================

print_header "Cleanup Complete!"

echo ""
echo "🧹 Cleanup Summary:"
echo "   • Gunicorn services: Stopped and removed"
echo "   • Nginx configurations: Removed (default restored)"
echo "   • SSL certificates: Removed"
echo "   • Log files: Cleaned"
echo "   • Socket directories: Removed"
echo "   • Virtual environments: Removed"
echo "   • Generated files: Removed (.env, gunicorn.conf.py, etc.)"
echo ""

print_status "Your system has been cleaned up and is ready for a fresh deployment!"
print_status "You can now run the Django deployment script again."

echo ""
echo "📝 Next Steps:"
echo "   1. Your source code is preserved in the project directories"
echo "   2. You may need to recreate your .env file"
echo "   3. Run the deployment script again when ready"
echo "   4. Your databases were selectively removed based on your choice"
echo ""

print_warning "Note: Your source code and git repositories are preserved"
print_warning "Only deployment-related configurations and generated files were removed"
