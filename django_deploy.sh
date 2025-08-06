#!/bin/bash

# Django EC2 Auto Deployment Script with Frontend Support
# Author: Automated Django Deployment
# Description: Automates Django deployment on EC2 with Gunicorn, Nginx, PostgreSQL and optional React frontend

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
cleanup_deployment() {
    print_header "Cleaning up failed deployment..."
    
    # Stop and remove services
    if [ -n "$APP_NAME" ]; then
        print_status "Stopping and removing services..."
        sudo systemctl stop gunicorn-$APP_NAME.service 2>/dev/null || true
        sudo systemctl disable gunicorn-$APP_NAME.service 2>/dev/null || true
        
        sudo rm -f /etc/systemd/system/gunicorn-$APP_NAME.service
        sudo rm -f /etc/tmpfiles.d/gunicorn-$APP_NAME.conf
        
        # Remove nginx configuration
        sudo rm -f /etc/nginx/sites-available/$APP_NAME
        sudo rm -f /etc/nginx/sites-enabled/$APP_NAME
        
        # Remove log directories
        sudo rm -rf /var/log/gunicorn/$APP_NAME-*
        sudo rm -rf /var/log/nginx/$APP_NAME.*
        
        # Remove socket directory
        sudo rm -rf /run/gunicorn
    fi
    
    # Drop only the specific database if it exists
    if [ -n "$DB_NAME" ] && [ -n "$DB_PASSWORD" ]; then
        print_status "Dropping database $DB_NAME..."
        export PGPASSWORD="$DB_PASSWORD"
        psql -h localhost -U postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\";" 2>/dev/null || true
    fi
    
    # Remove virtual environment
    if [ -n "$PROJECT_PATH" ] && [ -d "$PROJECT_PATH/venv" ]; then
        print_status "Removing virtual environment..."
        rm -rf "$PROJECT_PATH/venv"
    fi
    
    # Clean up frontend if configured
    if [ -n "$FRONTEND_APP_NAME" ]; then
        sudo rm -f /etc/nginx/sites-available/$FRONTEND_APP_NAME
        sudo rm -f /etc/nginx/sites-enabled/$FRONTEND_APP_NAME
        sudo rm -rf /var/www/$FRONTEND_DOMAIN
    fi
    
    sudo systemctl daemon-reload
    print_status "Cleanup completed. You can now run the script again."
}

# Trap function to cleanup on script exit with error
trap 'if [ $? -ne 0 ]; then cleanup_deployment; fi' EXIT

# Function to validate environment variables
validate_env_vars() {
    local env_file="$1"
    
    print_status "Validating environment variables..."
    
    # Source the environment file
    set -a
    source "$env_file"
    set +a
    
    # Test Django settings import
    cd "$PROJECT_PATH"
    source venv/bin/activate
    
    python3 -c "
import os
import django
from django.conf import settings
os.environ.setdefault('DJANGO_SETTINGS_MODULE', '$DJANGO_PROJECT.settings')
try:
    django.setup()
    print('✓ Django settings loaded successfully')
except Exception as e:
    print(f'✗ Django settings validation failed: {e}')
    exit(1)
" || return 1
    
    return 0
}

print_header "Django EC2 Auto Deployment Script"
echo "This script will automate your Django deployment on EC2"
echo "Run this script from your home directory (where your Django and frontend projects are located)"
echo ""

# =============================================================================
# USER INPUT COLLECTION
# =============================================================================

print_header "Configuration Setup"

# List available directories
echo "Available directories in $(pwd):"
ls -la | grep "^d" | awk '{print $9}' | grep -v "^\.$\|^\..$"
echo ""

prompt_input "Enter your app name (used for service names, logs, etc)" "APP_NAME" "This will be used to name all services (gunicorn-$APP_NAME, etc.)"

prompt_input "Enter your backend domain name (e.g., api.example.com)" "DOMAIN_NAME" "This is the domain that will serve your Django app"

prompt_input "Enter your Django project directory name (the folder containing manage.py)" "PROJECT_DIR" "The directory containing your Django project (e.g., Eduteka-Backend)"

prompt_input "Enter your Django project module name (for WSGI)" "DJANGO_PROJECT" "The Django project module name (e.g., eduteka_project)"

prompt_input "Enter PostgreSQL database name" "DB_NAME" "Database name that will be created for your app"

prompt_input "Enter PostgreSQL database password" "DB_PASSWORD" "Password for the postgres user to access the database"

# Environment Variables Configuration
print_header "Environment Variables Configuration"
echo "Your Django app requires environment variables to run properly."
echo "You can either:"
echo "1. Paste your complete .env file content"
echo "2. Enter variables manually (for simple setups)"
echo ""

read -p "Do you want to paste your complete .env file content? (y/n): " use_env_file

if [[ $use_env_file == "y" || $use_env_file == "Y" ]]; then
    echo ""
    echo "Please paste your complete .env file content below."
    echo "Press Ctrl+D when finished:"
    echo "----------------------------------------"
    
    # Read multiline input until EOF
    ENV_CONTENT=""
    while IFS= read -r line; do
        ENV_CONTENT="$ENV_CONTENT$line"$'\n'
    done
    
    # Remove the last newline if present
    ENV_CONTENT="${ENV_CONTENT%$'\n'}"
    
    print_status "Environment variables captured successfully!"
else
    print_status "Creating basic .env template..."
    print_warning "You'll need to manually add other environment variables after deployment"
    
    ENV_CONTENT="# Basic Environment Variables
# Database Configuration
DB_NAME=$DB_NAME
DB_USER=postgres
DB_PASSWORD=$DB_PASSWORD
DB_HOST=localhost
DB_PORT=5432

# Django Settings
DEBUG=False
ALLOWED_HOSTS=$DOMAIN_NAME,localhost,127.0.0.1

# Add your other environment variables here manually after deployment
# EMAIL_HOST_USER=your-email@domain.com
# EMAIL_HOST_PASSWORD=your-email-password
# STRIPE_SECRET_KEY=your-stripe-secret-key
# etc."
fi

# Confirm settings
print_header "Configuration Summary"
echo "App Name: $APP_NAME"
echo "Backend Domain: $DOMAIN_NAME"
echo "Project Directory: $PROJECT_DIR"
echo "Django Project Module: $DJANGO_PROJECT"
echo "Database Name: $DB_NAME"
echo "Database Password: $DB_PASSWORD"
echo "Environment Variables: $(echo "$ENV_CONTENT" | wc -l) lines configured"
echo ""
read -p "Continue with these settings? (y/n): " confirm

if [[ $confirm != "y" && $confirm != "Y" ]]; then
    print_error "Deployment cancelled by user"
    exit 1
fi

# Set paths - Use current directory as base
CURRENT_DIR=$(pwd)
PROJECT_PATH="$CURRENT_DIR/$PROJECT_DIR"
VENV_PATH="$PROJECT_PATH/venv"

# Verify project directory exists
if [ ! -d "$PROJECT_PATH" ]; then
    print_error "Project directory '$PROJECT_PATH' does not exist!"
    exit 1
fi

# Verify manage.py exists
if [ ! -f "$PROJECT_PATH/manage.py" ]; then
    print_error "manage.py not found in '$PROJECT_PATH'!"
    exit 1
fi

# =============================================================================
# SYSTEM UPDATES AND DEPENDENCIES
# =============================================================================

print_header "Installing System Dependencies"

print_status "Installing system dependencies..."
if ! sudo apt update && sudo apt upgrade -y; then
    print_error "Failed to update system packages"
    exit 1
fi

print_status "Installing Python and development tools..."
if ! sudo apt install -y python3 python3-pip python3-venv python3-dev build-essential libssl-dev libffi-dev libpq-dev libjpeg-dev zlib1g-dev; then
    print_error "Failed to install Python dependencies"
    exit 1
fi

print_status "Installing server components..."
if ! sudo apt install -y postgresql postgresql-contrib nginx git curl wget ccze multitail; then
    print_error "Failed to install server components"
    exit 1
fi

# =============================================================================
# POSTGRESQL SETUP
# =============================================================================

print_header "Configuring PostgreSQL Database"

print_status "Starting PostgreSQL service..."
if ! sudo systemctl start postgresql || ! sudo systemctl enable postgresql; then
    print_error "Failed to start PostgreSQL service"
    exit 1
fi

print_status "Checking if database '$DB_NAME' already exists..."
export PGPASSWORD="$DB_PASSWORD"
DB_EXISTS=$(sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -w "$DB_NAME" | wc -l)

if [ "$DB_EXISTS" -gt 0 ]; then
    print_warning "Database '$DB_NAME' already exists!"
    read -p "Do you want to drop and recreate it? (y/n): " drop_db
    
    if [[ $drop_db == "y" || $drop_db == "Y" ]]; then
        print_status "Dropping existing database '$DB_NAME'..."
        if ! sudo -u postgres psql -c "DROP DATABASE \"$DB_NAME\";"; then
            print_error "Failed to drop existing database $DB_NAME"
            exit 1
        fi
    else
        print_status "Using existing database '$DB_NAME'"
    fi
fi

if [ "$DB_EXISTS" -eq 0 ] || [[ $drop_db == "y" || $drop_db == "Y" ]]; then
    print_status "Creating database '$DB_NAME'..."
    if ! sudo -u postgres psql -c "CREATE DATABASE \"$DB_NAME\";"; then
        print_error "Failed to create database $DB_NAME"
        exit 1
    fi
fi

if ! sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$DB_PASSWORD';"; then
    print_error "Failed to set postgres user password"
    exit 1
fi

if ! sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_NAME\" TO postgres;"; then
    print_error "Failed to grant database privileges"
    exit 1
fi

sudo -u postgres psql -c "ALTER USER postgres CREATEDB;" || true

# Configure PostgreSQL with proper permissions
print_status "Configuring PostgreSQL settings..."
PG_VERSION=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP '\d+\.\d+' | head -1 | cut -d. -f1)
PG_CONFIG_PATH="/etc/postgresql/$PG_VERSION/main"

# Update postgresql.conf with sudo
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/" "$PG_CONFIG_PATH/postgresql.conf" 2>/dev/null || print_warning "Could not update postgresql.conf"
sudo sed -i "s/max_connections = 100/max_connections = 100/" "$PG_CONFIG_PATH/postgresql.conf" 2>/dev/null || true

# Ensure md5 authentication with proper sudo
if ! sudo grep -q "local   all             postgres                                md5" "$PG_CONFIG_PATH/pg_hba.conf" 2>/dev/null; then
    sudo sed -i "s/local   all             postgres                                peer/local   all             postgres                                md5/" "$PG_CONFIG_PATH/pg_hba.conf" 2>/dev/null || print_warning "Could not update pg_hba.conf"
fi

sudo systemctl restart postgresql

print_status "Testing database connection..."
export PGPASSWORD="$DB_PASSWORD"
if ! psql -h localhost -U postgres -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    print_error "Database connection failed!"
    exit 1
fi
print_status "Database connection successful!"

# =============================================================================
# PYTHON ENVIRONMENT SETUP
# =============================================================================

print_header "Setting up Python Environment"

if ! cd "$PROJECT_PATH"; then
    print_error "Failed to navigate to project directory: $PROJECT_PATH"
    exit 1
fi

print_status "Creating virtual environment..."
if ! python3 -m venv venv; then
    print_error "Failed to create virtual environment"
    exit 1
fi

if ! source venv/bin/activate; then
    print_error "Failed to activate virtual environment"
    exit 1
fi

print_status "Upgrading pip and installing dependencies..."
if ! pip install --upgrade pip; then
    print_error "Failed to upgrade pip"
    exit 1
fi

if ! pip install -r requirements.txt; then
    print_error "Failed to install requirements"
    exit 1
fi

if ! pip install gunicorn psycopg2-binary; then
    print_error "Failed to install gunicorn and psycopg2"
    exit 1
fi

# =============================================================================
# DJANGO CONFIGURATION
# =============================================================================

print_header "Configuring Django Application"

print_status "Creating .env file..."
# Generate Django secret key
DJANGO_SECRET_KEY=$(python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())")

# Create the .env file with user's content plus generated values
cat > .env << EOF
# Generated Django Secret Key
SECRET_KEY=$DJANGO_SECRET_KEY

$ENV_CONTENT
EOF

print_status "Validating environment variables..."
if ! validate_env_vars ".env"; then
    print_error "Environment variables validation failed!"
    echo ""
    print_warning "Common issues:"
    print_warning "1. Missing required environment variables"
    print_warning "2. Incorrect variable names or values"
    print_warning "3. Database connection parameters"
    echo ""
    print_error "Please check your .env file and try again"
    exit 1
fi

print_status "Running Django migrations..."
if ! python manage.py migrate; then
    print_error "Django migrations failed!"
    exit 1
fi

print_status "Collecting static files..."
if ! python manage.py collectstatic --noinput; then
    print_error "Static files collection failed!"
    exit 1
fi

# =============================================================================
# GUNICORN CONFIGURATION
# =============================================================================

print_header "Configuring Gunicorn"

print_status "Creating Gunicorn configuration..."

# Create the gunicorn configuration file
cat > /tmp/gunicorn.conf.py << EOF
# Gunicorn configuration for ${APP_NAME}
bind = "unix:/run/gunicorn/gunicorn-${APP_NAME}.sock"
workers = 3
worker_class = "sync"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 50
preload_app = True
timeout = 120
keepalive = 5
user = "ubuntu"
group = "ubuntu"
errorlog = "/var/log/gunicorn/${APP_NAME}-error.log"
accesslog = "/var/log/gunicorn/${APP_NAME}-access.log"
loglevel = "info"
EOF

# Copy the gunicorn config to project directory
cp /tmp/gunicorn.conf.py "$PROJECT_PATH/"
rm /tmp/gunicorn.conf.py

if [ $? -ne 0 ]; then
    print_error "Failed to create Gunicorn configuration"
    exit 1
fi

print_status "Creating log directories..."
if ! sudo mkdir -p /var/log/gunicorn; then
    print_error "Failed to create log directory"
    exit 1
fi
sudo chown ubuntu:ubuntu /var/log/gunicorn

if ! sudo mkdir -p /run/gunicorn; then
    print_error "Failed to create socket directory"
    exit 1
fi
sudo chown ubuntu:www-data /run/gunicorn
sudo chmod 755 /run/gunicorn

print_status "Creating systemd service for Gunicorn..."
sudo tee /etc/systemd/system/gunicorn-$APP_NAME.service > /dev/null << EOF
[Unit]
Description=Gunicorn instance to serve $APP_NAME
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=$PROJECT_PATH
Environment="PATH=$VENV_PATH/bin"
Environment="DJANGO_SETTINGS_MODULE=$DJANGO_PROJECT.settings"
ExecStart=$VENV_PATH/bin/gunicorn --config $PROJECT_PATH/gunicorn.conf.py $DJANGO_PROJECT.wsgi:application
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

if [ $? -ne 0 ]; then
    print_error "Failed to create Gunicorn systemd service"
    exit 1
fi

# =============================================================================
# NGINX CONFIGURATION FOR BACKEND
# =============================================================================

print_header "Configuring Nginx for Backend"

print_status "Removing default Nginx configuration..."
sudo rm -f /etc/nginx/sites-enabled/default

print_status "Creating Nginx configuration for $APP_NAME..."
sudo tee /etc/nginx/sites-available/$APP_NAME > /dev/null << EOF
# Backend HTTP Server
server {
    listen 80;
    server_name $DOMAIN_NAME;
    
    # Logging
    access_log /var/log/nginx/$APP_NAME.access.log;
    error_log /var/log/nginx/$APP_NAME.error.log;
    
    # Static files (served directly by nginx)
    location /static/ {
        alias $PROJECT_PATH/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Media files (served directly by nginx)
    location /media/ {
        alias $PROJECT_PATH/media/;
        expires 1y;
        add_header Cache-Control "public";
        access_log off;
    }
    
    # Django admin documentation
    location /yele-docs {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
        proxy_redirect off;
    }
    
    # All Django routes (including admin, api, docs, etc.)
    location / {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
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
}
EOF

if [ $? -ne 0 ]; then
    print_error "Failed to create Nginx configuration"
    exit 1
fi

print_status "Enabling Nginx site..."
if ! sudo ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/; then
    print_error "Failed to enable Nginx site"
    exit 1
fi

print_status "Testing Nginx configuration..."
if ! sudo nginx -t; then
    print_error "Nginx configuration test failed!"
    exit 1
fi

# =============================================================================
# FILE PERMISSIONS AND SECURITY
# =============================================================================

print_header "Setting up Security and Permissions"

print_status "Setting file permissions..."
sudo chown -R ubuntu:ubuntu $PROJECT_PATH
sudo chmod -R 755 $PROJECT_PATH
sudo chmod 644 $PROJECT_PATH/.env

# Add ubuntu to www-data group
sudo usermod -a -G www-data ubuntu

# Create tmpfiles configuration for socket directory
sudo tee /etc/tmpfiles.d/gunicorn-$APP_NAME.conf > /dev/null << EOF
d /run/gunicorn 0755 ubuntu www-data -
EOF

sudo systemd-tmpfiles --create

print_status "Configuring firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

# =============================================================================
# SERVICE STARTUP
# =============================================================================

print_header "Starting Backend Services"

print_status "Reloading systemd daemon..."
sudo systemctl daemon-reload

print_status "Starting Gunicorn service..."
sudo systemctl start gunicorn-$APP_NAME.service
sudo systemctl enable gunicorn-$APP_NAME.service

print_status "Starting Nginx..."
sudo systemctl start nginx
sudo systemctl enable nginx

# =============================================================================
# SERVICE VERIFICATION
# =============================================================================

print_header "Verifying Backend Deployment"

print_status "Checking service statuses..."

# Check Gunicorn
if sudo systemctl is-active --quiet gunicorn-$APP_NAME.service; then
    print_status "✓ Gunicorn service is running"
else
    print_error "✗ Gunicorn service failed to start"
    sudo systemctl status gunicorn-$APP_NAME.service
    exit 1
fi

# Check Nginx
if sudo systemctl is-active --quiet nginx; then
    print_status "✓ Nginx service is running"
else
    print_error "✗ Nginx service failed to start"
    exit 1
fi

# Check PostgreSQL
if sudo systemctl is-active --quiet postgresql; then
    print_status "✓ PostgreSQL service is running"
else
    print_error "✗ PostgreSQL service failed to start"
    exit 1
fi

# Check socket file
if [ -S "/run/gunicorn/gunicorn-$APP_NAME.sock" ]; then
    print_status "✓ Gunicorn socket created successfully"
else
    print_error "✗ Gunicorn socket not found"
    exit 1
fi

print_status "Testing application endpoint..."
sleep 5  # Give services time to fully start
if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN_NAME/" | grep -q "200\|301\|302"; then
    print_status "✓ Backend application is responding"
else
    print_warning "⚠ Backend application might not be responding correctly"
    print_status "Checking Gunicorn logs..."
    sudo journalctl -u gunicorn-$APP_NAME.service --no-pager -n 10
fi

# =============================================================================
# SSL CERTIFICATE SETUP
# =============================================================================

print_header "Setting up SSL Certificate"

print_status "Installing Certbot..."
if ! sudo apt install -y certbot python3-certbot-nginx; then
    print_error "Failed to install Certbot"
    exit 1
fi

print_status "Obtaining SSL certificate for $DOMAIN_NAME..."
if ! sudo certbot --nginx -d $DOMAIN_NAME --email chris@yelegroup.africa --agree-tos --non-interactive --redirect; then
    print_warning "SSL certificate installation failed. You can set it up manually later."
    print_warning "Run manually: sudo certbot --nginx -d $DOMAIN_NAME"
else
    # Setup auto-renewal
    print_status "Setting up SSL certificate auto-renewal..."
    (sudo crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | sudo crontab -
    print_status "✓ SSL certificate installed successfully"
fi

# =============================================================================
# FRONTEND DEPLOYMENT (OPTIONAL)
# =============================================================================

print_header "Frontend Deployment Setup"

echo ""
echo "Backend deployment completed! 🎉"
echo ""
read -p "Do you want to deploy a React frontend as well? (y/n): " deploy_frontend

if [[ $deploy_frontend == "y" || $deploy_frontend == "Y" ]]; then
    
    print_header "Frontend Configuration"
    
    # List available directories for frontend
    echo "Available directories for frontend:"
    for dir in "$CURRENT_DIR"/*; do
        if [ -d "$dir" ] && [ "$dir" != "$PROJECT_PATH" ]; then
            basename "$dir"
        fi
    done
    echo ""
    
    prompt_input "Enter frontend directory name" "FRONTEND_DIR" "The directory containing your React app with dist folder"
    
    FRONTEND_PATH="$CURRENT_DIR/$FRONTEND_DIR"
    
    # Verify frontend directory and dist folder exist
    if [ ! -d "$FRONTEND_PATH" ]; then
        print_error "Frontend directory '$FRONTEND_PATH' does not exist!"
        deploy_frontend="n"
    elif [ ! -d "$FRONTEND_PATH/dist" ]; then
        print_error "dist folder not found in '$FRONTEND_PATH'!"
        print_warning "Make sure to run 'npm run build' in your React app"
        deploy_frontend="n"
    fi
    
    if [[ $deploy_frontend == "y" || $deploy_frontend == "Y" ]]; then
        prompt_input "Enter frontend domain name (e.g., app.example.com)" "FRONTEND_DOMAIN" "This is the domain that will serve your React app"
        
        prompt_input "Enter frontend app name (for nginx config)" "FRONTEND_APP_NAME" "Used for naming nginx configuration files"
        
        print_header "Deploying React Frontend"
        
        # Create web directory and copy files
        print_status "Setting up frontend files..."
        sudo mkdir -p /var/www/$FRONTEND_DOMAIN
        sudo cp -r "$FRONTEND_PATH/dist"/* /var/www/$FRONTEND_DOMAIN/
        
        print_status "Configuring Nginx for React frontend..."
        
        # Create nginx configuration for frontend with backend proxy
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
    location ~ ^/(admin|api|docs|swagger|auth|accounts|yele-docs)/ {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
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
        alias $PROJECT_PATH/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Backend media files proxy
    location /media/ {
        alias $PROJECT_PATH/media/;
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
            print_error "Failed to create frontend Nginx configuration"
            exit 1
        fi
        
        print_status "Setting frontend directory permissions..."
        sudo chown -R www-data:www-data /var/www/$FRONTEND_DOMAIN
        sudo chmod -R 755 /var/www/$FRONTEND_DOMAIN
        
        print_status "Enabling frontend Nginx site..."
        if ! sudo ln -sf /etc/nginx/sites-available/$FRONTEND_APP_NAME /etc/nginx/sites-enabled/; then
            print_error "Failed to enable frontend Nginx site"
            exit 1
        fi
        
        print_status "Testing Nginx configuration with frontend..."
        if ! sudo nginx -t; then
            print_error "Nginx configuration test failed with frontend!"
            exit 1
        fi
        
        print_status "Reloading Nginx with frontend configuration..."
        if ! sudo systemctl reload nginx; then
            print_error "Failed to reload Nginx"
            exit 1
        fi
        
        print_header "Setting up SSL for Frontend"
        
        print_status "Obtaining SSL certificate for $FRONTEND_DOMAIN..."
        if ! sudo certbot --nginx -d $FRONTEND_DOMAIN --email chris@yelegroup.africa --agree-tos --non-interactive --redirect; then
            print_warning "Frontend SSL certificate installation failed. You can set it up manually later."
            print_warning "Run manually: sudo certbot --nginx -d $FRONTEND_DOMAIN"
        else
            print_status "✓ Frontend SSL certificate installed successfully"
        fi
        
        print_header "Verifying Frontend Deployment"
        
        print_status "Testing frontend endpoint..."
        sleep 3  # Give nginx time to reload
        if curl -s -o /dev/null -w "%{http_code}" "http://$FRONTEND_DOMAIN/" | grep -q "200\|301\|302"; then
            print_status "✓ Frontend is responding"
        else
            print_warning "⚠ Frontend might not be responding correctly"
            print_warning "Check nginx logs: sudo tail -f /var/log/nginx/$FRONTEND_APP_NAME.error.log"
        fi
        
        FRONTEND_DEPLOYED=true
    fi
else
    print_status "Skipping frontend deployment"
    FRONTEND_DEPLOYED=false
fi

# =============================================================================
# DEPLOYMENT UTILITIES
# =============================================================================

print_header "Creating Deployment Utilities"

print_status "Creating deployment update script..."
cat > /tmp/deploy_update.sh << 'EOF'
#!/bin/bash
# Auto-update deployment script

APP_NAME="APP_NAME_PLACEHOLDER"
PROJECT_PATH="PROJECT_PATH_PLACEHOLDER"
FRONTEND_DEPLOYED=FRONTEND_DEPLOYED_PLACEHOLDER
FRONTEND_PATH="FRONTEND_PATH_PLACEHOLDER"
FRONTEND_DOMAIN="FRONTEND_DOMAIN_PLACEHOLDER"

cd "$PROJECT_PATH"

echo "Pulling latest changes..."
git pull origin main

echo "Activating virtual environment..."
source venv/bin/activate

echo "Installing/updating dependencies..."
pip install -r requirements.txt

echo "Running migrations..."
python manage.py migrate

echo "Collecting static files..."
python manage.py collectstatic --noinput

echo "Restarting services..."
sudo systemctl restart gunicorn-$APP_NAME.service

echo "Backend deployment update completed!"

# Update frontend if deployed
if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo ""
    echo "Frontend detected. To update frontend:"
    echo "1. Rebuild your React app (npm run build)"
    echo "2. Copy new files: sudo cp -r $FRONTEND_PATH/dist/* /var/www/$FRONTEND_DOMAIN/"
    echo "3. Set permissions: sudo chown -R www-data:www-data /var/www/$FRONTEND_DOMAIN"
fi
EOF

# Replace placeholders with actual values
sed -i "s|APP_NAME_PLACEHOLDER|$APP_NAME|g" /tmp/deploy_update.sh
sed -i "s|PROJECT_PATH_PLACEHOLDER|$PROJECT_PATH|g" /tmp/deploy_update.sh
sed -i "s|FRONTEND_DEPLOYED_PLACEHOLDER|$FRONTEND_DEPLOYED|g" /tmp/deploy_update.sh
if [ "$FRONTEND_DEPLOYED" = true ]; then
    sed -i "s|FRONTEND_PATH_PLACEHOLDER|$FRONTEND_PATH|g" /tmp/deploy_update.sh
    sed -i "s|FRONTEND_DOMAIN_PLACEHOLDER|$FRONTEND_DOMAIN|g" /tmp/deploy_update.sh
fi

# Copy to project directory and make executable
cp /tmp/deploy_update.sh "$PROJECT_PATH/"
chmod +x "$PROJECT_PATH/deploy_update.sh"
rm /tmp/deploy_update.sh

print_status "Creating log monitoring script..."
cat > /tmp/monitor_logs.sh << 'EOF'
#!/bin/bash
# Log monitoring script for APP_NAME_PLACEHOLDER

echo "=== APP_NAME_PLACEHOLDER Log Monitor ==="
echo "Press Ctrl+C to stop"
echo "=========================="

# Monitor Gunicorn access logs with color coding
tail -f /var/log/gunicorn/APP_NAME_PLACEHOLDER-access.log | while read line; do
    timestamp=$(echo "$line" | awk '{print $1, $2}')
    request=$(echo "$line" | grep -o '"[^"]*"' | head -1)
    status=$(echo "$line" | awk '{print $9}')
    
    # Color code based on status
    if [[ $status =~ ^2 ]]; then
        color="\033[32m"  # Green for 2xx
    elif [[ $status =~ ^3 ]]; then
        color="\033[33m"  # Yellow for 3xx
    elif [[ $status =~ ^4 ]]; then
        color="\033[31m"  # Red for 4xx
    elif [[ $status =~ ^5 ]]; then
        color="\033[35m"  # Magenta for 5xx
    else
        color="\033[0m"   # Default
    fi
    
    echo -e "${color}[$timestamp] $status $request\033[0m"
done
EOF

# Replace placeholders
sed -i "s|APP_NAME_PLACEHOLDER|$APP_NAME|g" /tmp/monitor_logs.sh

# Copy to project directory and make executable
cp /tmp/monitor_logs.sh "$PROJECT_PATH/"
chmod +x "$PROJECT_PATH/monitor_logs.sh"
rm /tmp/monitor_logs.sh

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

# Disable the trap before successful completion
trap - EXIT

print_header "Deployment Complete!"

echo ""
echo "🎉 Your Django application has been successfully deployed!"
echo ""
echo "📋 Backend Deployment Summary:"
echo "   • App Name: $APP_NAME"
echo "   • Domain: https://$DOMAIN_NAME"
echo "   • Project Path: $PROJECT_PATH"
echo "   • Database: $DB_NAME"
echo "   • Swagger Docs: https://$DOMAIN_NAME/yele-docs"
echo ""

if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo "📋 Frontend Deployment Summary:"
    echo "   • Frontend Domain: https://$FRONTEND_DOMAIN"
    echo "   • Frontend Path: /var/www/$FRONTEND_DOMAIN"
    echo "   • Frontend Config: $FRONTEND_APP_NAME"
    echo "   • API Access: https://$FRONTEND_DOMAIN/yele-docs"
    echo ""
fi

echo "🔧 Service Management Commands:"
echo "   • Restart Backend: sudo systemctl restart gunicorn-$APP_NAME.service"
echo "   • View Backend Logs: sudo journalctl -u gunicorn-$APP_NAME.service -f"
echo "   • Monitor Requests: cd $PROJECT_PATH && ./monitor_logs.sh"
echo "   • Update Deployment: cd $PROJECT_PATH && ./deploy_update.sh"
echo ""
echo "📁 Important Files Created:"
echo "   • Gunicorn Service: /etc/systemd/system/gunicorn-$APP_NAME.service"
echo "   • Backend Nginx Config: /etc/nginx/sites-available/$APP_NAME"

if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo "   • Frontend Nginx Config: /etc/nginx/sites-available/$FRONTEND_APP_NAME"
fi

echo "   • App Logs: /var/log/gunicorn/$APP_NAME-*.log"
echo "   • Nginx Logs: /var/log/nginx/$APP_NAME.*.log"

if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo "   • Frontend Logs: /var/log/nginx/$FRONTEND_APP_NAME.*.log"
fi

echo ""
echo "🔗 Quick Tests:"
echo "   • Backend API: https://$DOMAIN_NAME"
echo "   • Admin Panel: https://$DOMAIN_NAME/admin/"
echo "   • API Documentation: https://$DOMAIN_NAME/yele-docs"

if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo "   • Frontend App: https://$FRONTEND_DOMAIN"
    echo "   • API from Frontend: https://$FRONTEND_DOMAIN/yele-docs"
fi

echo ""
echo "📝 Next Steps:"
echo "   1. Create Django superuser: cd $PROJECT_PATH && source venv/bin/activate && python manage.py createsuperuser"
echo "   2. Test all endpoints including /yele-docs"
echo "   3. Verify SSL certificates are working"
echo "   4. Update your environment variables if needed"

if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo "   5. Test API connectivity from frontend"
    echo "   6. Verify React routing works correctly"
fi

echo ""

print_warning "Important Notes:"
print_warning "• The script does not modify your repository code"
print_warning "• All necessary configurations are done in system files only"
print_warning "• Your /yele-docs route should work if properly configured in your Django app"
print_warning "• SSL certificates are automatically configured"

if [ "$FRONTEND_DEPLOYED" = true ]; then
    print_warning "• Frontend proxies backend routes including /yele-docs"
fi

echo ""
echo "🚨 Troubleshooting Commands:"
echo "   • Check backend status: sudo systemctl status gunicorn-$APP_NAME.service"
echo "   • Check nginx status: sudo systemctl status nginx"
echo "   • Check backend logs: sudo journalctl -u gunicorn-$APP_NAME.service -n 50"
echo "   • Check nginx error logs: sudo tail -f /var/log/nginx/$APP_NAME.error.log"

if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo "   • Check frontend logs: sudo tail -f /var/log/nginx/$FRONTEND_APP_NAME.error.log"
fi

echo "   • Test socket connection: curl --unix-socket /run/gunicorn/gunicorn-$APP_NAME.sock http://localhost/"
echo "   • Test /yele-docs: curl -I https://$DOMAIN_NAME/yele-docs"
echo ""
print_status "Deployment script completed successfully! 🚀"