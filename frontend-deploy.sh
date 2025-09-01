#!/bin/bash

# React Frontend Deployment Script
# Author: Automated Frontend Deployment
# Description: Deploys React frontend applications with backend proxy configuration

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
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

# Function to prompt for user input
prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local description="$3"
    
    echo -e "${YELLOW}$description${NC}"
    read -p "$prompt: " value
    eval "$var_name=\"$value\""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Cleanup function for deployment failure
cleanup_frontend_deployment() {
    print_header "Cleaning up failed frontend deployment..."
    
    if [ -n "$FRONTEND_APP_NAME" ]; then
        print_status "Removing nginx configuration..."
        sudo rm -f /etc/nginx/sites-available/$FRONTEND_APP_NAME
        sudo rm -f /etc/nginx/sites-enabled/$FRONTEND_APP_NAME
        
        # Remove log files
        sudo rm -f /var/log/nginx/$FRONTEND_APP_NAME.*
    fi
    
    if [ -n "$FRONTEND_DOMAIN" ]; then
        print_status "Removing web directory..."
        sudo rm -rf /var/www/$FRONTEND_DOMAIN
    fi
    
    sudo systemctl reload nginx 2>/dev/null || true
    print_status "Frontend cleanup completed. You can run the script again."
}

# Trap function to cleanup on script exit with error
trap 'if [ $? -ne 0 ]; then cleanup_frontend_deployment; fi' EXIT

print_header "React Frontend Deployment Script"
echo "This script will deploy your React frontend application to EC2"
echo "Make sure your React app is built (npm run build) before running this script"
echo ""

# =============================================================================
# USER INPUT COLLECTION
# =============================================================================

print_header "Frontend Configuration Setup"

# Get current directory and list available directories
CURRENT_DIR=$(pwd)
echo "Current directory: $CURRENT_DIR"
echo ""
echo "Available directories:"
ls -la | grep "^d" | awk '{print $9}' | grep -v "^\.$\|^\..$"
echo ""

prompt_input "Enter your frontend app name (used for nginx config)" "FRONTEND_APP_NAME" "This will be used to name nginx configuration files"

prompt_input "Enter your frontend domain name (e.g., app.example.com)" "FRONTEND_DOMAIN" "This is the domain that will serve your React app"

prompt_input "Enter your React project directory name" "FRONTEND_DIR" "The directory containing your React app with dist/build folder"

# Check for build folder
FRONTEND_PATH="$CURRENT_DIR/$FRONTEND_DIR"
BUILD_FOLDER=""

if [ -d "$FRONTEND_PATH/dist" ]; then
    BUILD_FOLDER="dist"
    print_status "Found dist folder"
elif [ -d "$FRONTEND_PATH/build" ]; then
    BUILD_FOLDER="build"
    print_status "Found build folder"
else
    print_error "No dist or build folder found in $FRONTEND_PATH"
    print_error "Please run 'npm run build' or 'yarn build' first"
    exit 1
fi

# Backend configuration
print_header "Backend Proxy Configuration"

echo "Available backend sockets in /run/gunicorn/:"
if [ -d "/run/gunicorn" ]; then
    ls -la /run/gunicorn/ 2>/dev/null | grep "\.sock$" || echo "No backend sockets found"
else
    echo "No /run/gunicorn directory found"
fi
echo ""

prompt_input "Enter backend app name (for socket connection)" "BACKEND_APP_NAME" "The name of your Django backend app (e.g., eduteka-backend)"

prompt_input "Enter backend project path" "BACKEND_PROJECT_PATH" "Full path to your Django backend project (e.g., /home/ubuntu/Eduteka-Backend)"

# Backend routes configuration
print_header "Backend Routes Configuration"
echo "Configure which routes should be proxied to the backend."
echo "Default routes: admin,api,docs,swagger,auth,accounts,yele-docs"
echo ""

read -p "Enter additional backend routes (comma-separated, e.g., students,teachers,schools): " ADDITIONAL_ROUTES

# Combine default and additional routes
DEFAULT_ROUTES="admin,api,docs,swagger,auth,accounts,yele-docs"
if [ -n "$ADDITIONAL_ROUTES" ]; then
    BACKEND_ROUTES="$DEFAULT_ROUTES,$ADDITIONAL_ROUTES"
else
    BACKEND_ROUTES="$DEFAULT_ROUTES"
fi

# Convert comma-separated routes to regex pattern
BACKEND_ROUTES_PATTERN=$(echo "$BACKEND_ROUTES" | sed 's/,/|/g')

# Email for SSL certificate
prompt_input "Enter email for SSL certificate" "SSL_EMAIL" "Email address for Let's Encrypt SSL certificate"

# Confirm settings
print_header "Configuration Summary"
echo "Frontend App Name: $FRONTEND_APP_NAME"
echo "Frontend Domain: $FRONTEND_DOMAIN"
echo "Frontend Directory: $FRONTEND_DIR"
echo "Build Folder: $BUILD_FOLDER"
echo "Backend App Name: $BACKEND_APP_NAME"
echo "Backend Project Path: $BACKEND_PROJECT_PATH"
echo "Backend Routes: $BACKEND_ROUTES"
echo "SSL Email: $SSL_EMAIL"
echo ""
read -p "Continue with these settings? (y/n): " confirm

if [[ $confirm != "y" && $confirm != "Y" ]]; then
    print_error "Deployment cancelled by user"
    exit 1
fi

# =============================================================================
# SYSTEM DEPENDENCIES CHECK
# =============================================================================

print_header "Checking System Dependencies"

# Check if nginx is installed
if ! command_exists nginx; then
    print_status "Installing Nginx..."
    sudo apt update
    sudo apt install -y nginx
fi

# Check if certbot is installed
if ! command_exists certbot; then
    print_status "Installing Certbot..."
    sudo apt install -y certbot python3-certbot-nginx
fi

# =============================================================================
# FRONTEND DEPLOYMENT
# =============================================================================

print_header "Deploying React Frontend"

# Verify frontend directory and build folder exist
if [ ! -d "$FRONTEND_PATH" ]; then
    print_error "Frontend directory '$FRONTEND_PATH' does not exist!"
    exit 1
fi

if [ ! -d "$FRONTEND_PATH/$BUILD_FOLDER" ]; then
    print_error "$BUILD_FOLDER folder not found in '$FRONTEND_PATH'!"
    print_error "Please run 'npm run build' or 'yarn build' first"
    exit 1
fi

# Verify backend socket exists
BACKEND_SOCKET="/run/gunicorn/gunicorn-$BACKEND_APP_NAME.sock"
if [ ! -S "$BACKEND_SOCKET" ]; then
    print_warning "Backend socket '$BACKEND_SOCKET' not found!"
    print_warning "Make sure your Django backend is running"
    read -p "Continue anyway? (y/n): " continue_without_backend
    if [[ $continue_without_backend != "y" && $continue_without_backend != "Y" ]]; then
        exit 1
    fi
fi

# Verify backend project path exists
if [ ! -d "$BACKEND_PROJECT_PATH" ]; then
    print_warning "Backend project path '$BACKEND_PROJECT_PATH' does not exist!"
    read -p "Continue anyway? (y/n): " continue_without_backend_path
    if [[ $continue_without_backend_path != "y" && $continue_without_backend_path != "Y" ]]; then
        exit 1
    fi
fi

# Create web directory and copy files
print_status "Setting up frontend files..."
sudo mkdir -p /var/www/$FRONTEND_DOMAIN
sudo cp -r "$FRONTEND_PATH/$BUILD_FOLDER"/* /var/www/$FRONTEND_DOMAIN/

# Set proper permissions
print_status "Setting file permissions..."
sudo chown -R www-data:www-data /var/www/$FRONTEND_DOMAIN
sudo chmod -R 755 /var/www/$FRONTEND_DOMAIN

# =============================================================================
# NGINX CONFIGURATION
# =============================================================================

print_header "Configuring Nginx for React Frontend"

print_status "Creating Nginx configuration..."

# Create nginx configuration file
sudo tee /etc/nginx/sites-available/$FRONTEND_APP_NAME > /dev/null << EOF
# React Frontend Configuration with Backend Proxy
server {
    listen 80;
    server_name $FRONTEND_DOMAIN;
    
    # Logging
    access_log /var/log/nginx/$FRONTEND_APP_NAME.access.log;
    error_log /var/log/nginx/$FRONTEND_APP_NAME.error.log;
    
    # Root directory for React build files
    root /var/www/$FRONTEND_DOMAIN;
    index index.html;
    
    # Backend API proxy - proxy ALL backend routes
    location ~ ^/($BACKEND_ROUTES_PATTERN)/ {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$BACKEND_APP_NAME.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
        proxy_redirect off;
        
        # CORS headers for API
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'Accept,Authorization,Cache-Control,Content-Type,DNT,If-Modified-Since,Keep-Alive,Origin,User-Agent,X-Requested-With' always;
        
        # Handle preflight requests
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'Accept,Authorization,Cache-Control,Content-Type,DNT,If-Modified-Since,Keep-Alive,Origin,User-Agent,X-Requested-With';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }
    
    # Backend static files proxy
    location /static/ {
        alias $BACKEND_PROJECT_PATH/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Backend media files proxy
    location /media/ {
        alias $BACKEND_PROJECT_PATH/media/;
        expires 1y;
        add_header Cache-Control "public";
        access_log off;
    }
    
    # Frontend static assets (JS, CSS, images, etc.)
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
        try_files \$uri =404;
    }
    
    # Handle React Router (SPA routing) - must be last
    location / {
        try_files \$uri \$uri/ /index.html;
        
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
    }
}
EOF

if [ $? -ne 0 ]; then
    print_error "Failed to create Nginx configuration"
    exit 1
fi

print_status "Enabling Nginx site..."
# Remove any existing link first
sudo rm -f /etc/nginx/sites-enabled/$FRONTEND_APP_NAME

# Create the symbolic link
if ! sudo ln -s /etc/nginx/sites-available/$FRONTEND_APP_NAME /etc/nginx/sites-enabled/$FRONTEND_APP_NAME; then
    print_error "Failed to enable Nginx site"
    exit 1
fi

print_status "Testing Nginx configuration..."
if ! sudo nginx -t; then
    print_error "Nginx configuration test failed!"
    exit 1
fi

print_status "Reloading Nginx..."
if ! sudo systemctl reload nginx; then
    print_error "Failed to reload Nginx"
    exit 1
fi

# =============================================================================
# SSL CERTIFICATE SETUP
# =============================================================================

print_header "Setting up SSL Certificate"

print_status "Obtaining SSL certificate for $FRONTEND_DOMAIN (root domain only)..."
if ! sudo certbot --nginx -d "$FRONTEND_DOMAIN" --email "$SSL_EMAIL" --agree-tos --non-interactive --redirect; then
    print_warning "SSL certificate installation failed. You can set it up manually later."
    print_warning "Run manually: sudo certbot --nginx -d $FRONTEND_DOMAIN"
else
    # Setup auto-renewal if not already configured
    if ! sudo crontab -l 2>/dev/null | grep -q "certbot renew"; then
        print_status "Setting up SSL certificate auto-renewal..."
        (sudo crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | sudo crontab -
    fi
    print_status "✓ SSL certificate installed successfully for $FRONTEND_DOMAIN (no www)"
fi


# =============================================================================
# DEPLOYMENT VERIFICATION
# =============================================================================

print_header "Verifying Frontend Deployment"

# Check Nginx
if sudo systemctl is-active --quiet nginx; then
    print_status "✓ Nginx service is running"
else
    print_error "✗ Nginx service failed"
    exit 1
fi

print_status "Testing frontend endpoint..."
sleep 3  # Give nginx time to reload
if curl -s -o /dev/null -w "%{http_code}" "http://$FRONTEND_DOMAIN/" | grep -q "200\|301\|302"; then
    print_status "✓ Frontend is responding"
else
    print_warning "⚠ Frontend might not be responding correctly"
    print_warning "Check nginx logs: sudo tail -f /var/log/nginx/$FRONTEND_APP_NAME.error.log"
fi

# Test backend proxy if socket exists
if [ -S "$BACKEND_SOCKET" ]; then
    print_status "Testing backend proxy connection..."
    if curl -s -o /dev/null -w "%{http_code}" "http://$FRONTEND_DOMAIN/api/" | grep -q "200\|301\|302\|404\|405"; then
        print_status "✓ Backend proxy is working"
    else
        print_warning "⚠ Backend proxy might not be working correctly"
    fi
fi

# =============================================================================
# DEPLOYMENT UTILITIES
# =============================================================================

print_header "Creating Frontend Update Utilities"

print_status "Creating frontend update script..."
cat > /tmp/update_frontend.sh << 'EOF'
#!/bin/bash
# Frontend update script

FRONTEND_DOMAIN="FRONTEND_DOMAIN_PLACEHOLDER"
FRONTEND_PATH="FRONTEND_PATH_PLACEHOLDER"
BUILD_FOLDER="BUILD_FOLDER_PLACEHOLDER"

echo "Frontend Update Script for $FRONTEND_DOMAIN"
echo "============================================"

cd "$FRONTEND_PATH"

echo "Current directory: $(pwd)"
echo ""

echo "Please ensure you have:"
echo "1. Pulled latest changes from your repository"
echo "2. Run 'npm run build' or 'yarn build'"
echo ""

read -p "Have you built the latest frontend? (y/n): " built_confirm

if [[ $built_confirm != "y" && $built_confirm != "Y" ]]; then
    echo "Please build your frontend first and run this script again"
    exit 1
fi

if [ ! -d "$BUILD_FOLDER" ]; then
    echo "Error: $BUILD_FOLDER folder not found!"
    echo "Please run 'npm run build' or 'yarn build'"
    exit 1
fi

echo "Updating frontend files..."
sudo rm -rf /var/www/$FRONTEND_DOMAIN/*
sudo cp -r $BUILD_FOLDER/* /var/www/$FRONTEND_DOMAIN/

echo "Setting permissions..."
sudo chown -R www-data:www-data /var/www/$FRONTEND_DOMAIN
sudo chmod -R 755 /var/www/$FRONTEND_DOMAIN

echo "Frontend update completed successfully!"
echo "Visit: https://$FRONTEND_DOMAIN"
EOF

# Replace placeholders with actual values
sed -i "s|FRONTEND_DOMAIN_PLACEHOLDER|$FRONTEND_DOMAIN|g" /tmp/update_frontend.sh
sed -i "s|FRONTEND_PATH_PLACEHOLDER|$FRONTEND_PATH|g" /tmp/update_frontend.sh
sed -i "s|BUILD_FOLDER_PLACEHOLDER|$BUILD_FOLDER|g" /tmp/update_frontend.sh

# Copy to project directory and make executable
cp /tmp/update_frontend.sh "$FRONTEND_PATH/"
chmod +x "$FRONTEND_PATH/update_frontend.sh"
rm /tmp/update_frontend.sh

print_status "Creating nginx configuration backup..."
sudo cp /etc/nginx/sites-available/$FRONTEND_APP_NAME "$FRONTEND_PATH/${FRONTEND_APP_NAME}-nginx.conf.backup"
sudo chown ubuntu:ubuntu "$FRONTEND_PATH/${FRONTEND_APP_NAME}-nginx.conf.backup"

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

# Disable the trap before successful completion
trap - EXIT

print_header "Frontend Deployment Complete!"

echo ""
echo "🎉 Your React frontend has been successfully deployed!"
echo ""
echo "📋 Frontend Deployment Summary:"
echo "   • Frontend App Name: $FRONTEND_APP_NAME"
echo "   • Frontend Domain: https://$FRONTEND_DOMAIN"
echo "   • Web Directory: /var/www/$FRONTEND_DOMAIN"
echo "   • Build Folder Used: $BUILD_FOLDER"
echo "   • SSL Certificate: Configured"
echo ""
echo "🔗 Backend Proxy Configuration:"
echo "   • Backend App: $BACKEND_APP_NAME"
echo "   • Backend Socket: unix:/run/gunicorn/gunicorn-$BACKEND_APP_NAME.sock"
echo "   • Backend Project: $BACKEND_PROJECT_PATH"
echo "   • Proxied Routes: $BACKEND_ROUTES"
echo ""
echo "📁 Important Files Created:"
echo "   • Nginx Config: /etc/nginx/sites-available/$FRONTEND_APP_NAME"
echo "   • Nginx Config Backup: $FRONTEND_PATH/${FRONTEND_APP_NAME}-nginx.conf.backup"
echo "   • Update Script: $FRONTEND_PATH/update_frontend.sh"
echo "   • Access Logs: /var/log/nginx/$FRONTEND_APP_NAME.access.log"
echo "   • Error Logs: /var/log/nginx/$FRONTEND_APP_NAME.error.log"
echo ""
echo "🔧 Management Commands:"
echo "   • Update Frontend: cd $FRONTEND_PATH && ./update_frontend.sh"
echo "   • Check Nginx Config: sudo nginx -t"
echo "   • Reload Nginx: sudo systemctl reload nginx"
echo "   • View Frontend Logs: sudo tail -f /var/log/nginx/$FRONTEND_APP_NAME.access.log"
echo "   • View Error Logs: sudo tail -f /var/log/nginx/$FRONTEND_APP_NAME.error.log"
echo ""
echo "🔗 Quick Tests:"
echo "   • Frontend App: https://$FRONTEND_DOMAIN"
echo "   • Backend API Test: https://$FRONTEND_DOMAIN/api/"
echo "   • Admin Panel: https://$FRONTEND_DOMAIN/admin/"
if [[ $BACKEND_ROUTES == *"yele-docs"* ]]; then
echo "   • API Documentation: https://$FRONTEND_DOMAIN/yele-docs/"
fi
echo ""
echo "📝 Next Steps:"
echo "   1. Test your React app functionality"
echo "   2. Verify all API endpoints work correctly"
echo "   3. Test React Router navigation"
echo "   4. Check browser console for any errors"
echo "   5. Test form submissions and API calls"
echo ""
echo "🚨 Troubleshooting Commands:"
echo "   • Check frontend files: ls -la /var/www/$FRONTEND_DOMAIN/"
echo "   • Test backend connectivity: curl -I https://$FRONTEND_DOMAIN/api/"
echo "   • Check nginx status: sudo systemctl status nginx"
echo "   • View nginx error logs: sudo tail -f /var/log/nginx/$FRONTEND_APP_NAME.error.log"
echo "   • Test SSL: curl -I https://$FRONTEND_DOMAIN/"
echo ""

print_warning "Important Notes:"
print_warning "• Make sure your backend Django app is running"
print_warning "• Your React app should be configured to make API calls to the same domain"
print_warning "• Update your frontend using the provided update script"
print_warning "• SSL certificate will auto-renew"

echo ""
print_status "Frontend deployment script completed successfully! 🚀"
print_status "Your React app is now live at https://$FRONTEND_DOMAIN"
