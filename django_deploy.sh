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
    
    # Remove generated files
    if [ -n "$PROJECT_PATH" ]; then
        rm -f "$PROJECT_PATH/.env"
        rm -f "$PROJECT_PATH/gunicorn.conf.py"
        rm -f "$PROJECT_PATH/deploy_update.sh"
        rm -f "$PROJECT_PATH/monitor_logs.sh"
    fi
    
    # Clean up frontend if configured
    if [ -n "$FRONTEND_APP_NAME" ]; then
        sudo rm -f /etc/nginx/sites-available/$FRONTEND_APP_NAME
        sudo rm -f /etc/nginx/sites-enabled/$FRONTEND_APP_NAME
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
echo "Make sure you've cloned your Django project in the current directory"
echo ""

# =============================================================================
# USER INPUT COLLECTION
# =============================================================================

print_header "Configuration Setup"

# Get current directory name as default app name
current_dir=$(basename "$PWD")

prompt_input "Enter your app name (used for service names, logs, etc)" "APP_NAME" "This will be used to name all services (gunicorn-$APP_NAME, etc.)"

prompt_input "Enter your domain name (e.g., api.example.com)" "DOMAIN_NAME" "This is the domain that will serve your Django app"

prompt_input "Enter your Django project directory name (where manage.py is located)" "PROJECT_DIR" "The directory containing your Django project (usually the repo name)"

prompt_input "Enter your Django project module name (for WSGI)" "DJANGO_PROJECT" "The Django project module name (the directory containing wsgi.py)"

prompt_input "Enter PostgreSQL database name" "DB_NAME" "Database name that will be created for your app"

prompt_input "Enter PostgreSQL database password" "DB_PASSWORD" "Password for the postgres user to access the database"

prompt_input "Enter Django URLs module path (e.g., myproject.urls or api.urls)" "DJANGO_URLS_MODULE" "The path to your Django URLs configuration for proper routing"

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
    ENV_CONTENT=$(cat)
    
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
echo "Domain: $DOMAIN_NAME"
echo "Project Directory: $PROJECT_DIR"
echo "Django Project Module: $DJANGO_PROJECT"
echo "Django URLs Module: $DJANGO_URLS_MODULE"
echo "Database Name: $DB_NAME"
echo "Database Password: $DB_PASSWORD"
echo "Environment Variables: $(echo "$ENV_CONTENT" | wc -l) lines configured"
echo ""
read -p "Continue with these settings? (y/n): " confirm

if [[ $confirm != "y" && $confirm != "Y" ]]; then
    print_error "Deployment cancelled by user"
    exit 1
fi

# Set paths
PROJECT_PATH="/home/ubuntu/$PROJECT_DIR"
VENV_PATH="$PROJECT_PATH/venv"

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
DB_EXISTS=$(psql -h localhost -U postgres -lqt 2>/dev/null | cut -d \| -f 1 | grep -w "$DB_NAME" | wc -l)

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

print_status "Collecting static files (including Swagger docs)..."
if ! python manage.py collectstatic --noinput; then
    print_error "Static files collection failed!"
    exit 1
fi

# =============================================================================
# GUNICORN CONFIGURATION
# =============================================================================

print_header "Configuring Gunicorn"

print_status "Creating Gunicorn configuration..."

# Create the gunicorn configuration file using cat with proper escaping
cat > gunicorn.conf.py << EOF
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
# HTTP Server
server {
    listen 80;
    server_name $DOMAIN_NAME;
    
    # Logging
    access_log /var/log/nginx/$APP_NAME.access.log;
    error_log /var/log/nginx/$APP_NAME.error.log;
    
    # Swagger Documentation (served at /yele-docs)
    location /yele-docs/ {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
    }
    
    # API routes (all Django URLs)
    location /api/ {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
    }
    
    # Admin interface
    location /admin/ {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
    }
    
    # All other Django routes
    location / {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
    }
    
    # Static files
    location /static/ {
        alias $PROJECT_PATH/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Media files
    location /media/ {
        alias $PROJECT_PATH/media/;
        expires 1y;
        add_header Cache-Control "public";
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
# SSL CERTIFICATE SETUP
# =============================================================================

print_header "Setting up SSL Certificate"

print_status "Installing Certbot..."
if ! sudo apt install -y certbot python3-certbot-nginx; then
    print_error "Failed to install Certbot"
    exit 1
fi

print_status "Obtaining SSL certificate for $DOMAIN_NAME..."
if ! sudo certbot --nginx -d $DOMAIN_NAME --non-interactive --agree-tos --email admin@$DOMAIN_NAME; then
    print_warning "SSL certificate installation failed. You can set it up manually later."
    print_warning "Command: sudo certbot --nginx -d $DOMAIN_NAME"
else
    # Setup auto-renewal
    print_status "Setting up SSL certificate auto-renewal..."
    (sudo crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | sudo crontab -
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
if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN_NAME/" | grep -q "200\|301\|302"; then
    print_status "✓ Application is responding"
else
    print_warning "⚠ Application might not be responding correctly"
fi

print_status "Testing Swagger documentation endpoint..."
if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN_NAME/yele-docs/" | grep -q "200\|301\|302"; then
    print_status "✓ Swagger documentation is accessible at /yele-docs/"
else
    print_warning "⚠ Swagger documentation might not be accessible at /yele-docs/"
fi

# =============================================================================
# FRONTEND DEPLOYMENT (OPTIONAL)
# =============================================================================

print_header "Frontend Deployment Setup"

echo ""
echo "Backend deployment completed successfully! 🎉"
echo ""
read -p "Do you want to deploy a React frontend as well? (y/n): " deploy_frontend

if [[ $deploy_frontend == "y" || $deploy_frontend == "Y" ]]; then
    
    print_header "Frontend Configuration"
    
    # Check for React apps at the same level as backend
    PARENT_DIR=$(dirname "$PROJECT_PATH")
    echo "Scanning for React apps in: $PARENT_DIR"
    
    # Find directories with dist folder (built React apps)
    REACT_APPS=()
    for dir in "$PARENT_DIR"/*; do
        if [ -d "$dir" ] && [ -d "$dir/dist" ] && [ "$dir" != "$PROJECT_PATH" ]; then
            REACT_APPS+=("$(basename "$dir")")
        fi
    done
    
    if [ ${#REACT_APPS[@]} -eq 0 ]; then
        print_warning "No React apps with 'dist' folder found at the same level as backend"
        print_warning "Make sure your React app is built (npm run build) and has a 'dist' folder"
        read -p "Enter the frontend directory name manually: " FRONTEND_DIR
        FRONTEND_PATH="$PARENT_DIR/$FRONTEND_DIR"
        
        if [ ! -d "$FRONTEND_PATH/dist" ]; then
            print_error "Frontend directory '$FRONTEND_PATH' or dist folder doesn't exist"
            print_warning "Skipping frontend deployment"
            deploy_frontend="n"
        fi
    else
        echo "Found React apps with dist folders:"
        for i in "${!REACT_APPS[@]}"; do
            echo "$((i+1)). ${REACT_APPS[i]}"
        done
        echo ""
        read -p "Select frontend app (1-${#REACT_APPS[@]}): " app_choice
        
        if [[ $app_choice -ge 1 && $app_choice -le ${#REACT_APPS[@]} ]]; then
            FRONTEND_DIR="${REACT_APPS[$((app_choice-1))]}"
            FRONTEND_PATH="$PARENT_DIR/$FRONTEND_DIR"
        else
            print_error "Invalid selection"
            deploy_frontend="n"
        fi
    fi
    
    if [[ $deploy_frontend == "y" || $deploy_frontend == "Y" ]]; then
        prompt_input "Enter frontend domain name (e.g., app.example.com)" "FRONTEND_DOMAIN" "This is the domain that will serve your React app"
        
        prompt_input "Enter frontend app name (for nginx config)" "FRONTEND_APP_NAME" "Used for naming nginx configuration files"
        
        print_header "Deploying React Frontend"
        
        print_status "Configuring Nginx for React frontend..."
        
        # Create nginx configuration for frontend
        sudo tee /etc/nginx/sites-available/$FRONTEND_APP_NAME > /dev/null << EOF
# React Frontend Configuration
server {
    listen 80;
    server_name $FRONTEND_DOMAIN;
    
    # Logging
    access_log /var/log/nginx/$FRONTEND_APP_NAME.access.log;
    error_log /var/log/nginx/$FRONTEND_APP_NAME.error.log;
    
    # Root directory for React build files
    root $FRONTEND_PATH/dist;
    index index.html;
    
    # Handle React Router (SPA routing)
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    # API proxy to backend
    location /api/ {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
    }
    
    # Swagger docs proxy to backend
    location /yele-docs/ {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
    }
    
    # Admin interface proxy to backend
    location /admin/ {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-$APP_NAME.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
    }
    
    # Static files for backend
    location /static/ {
        alias $PROJECT_PATH/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Media files for backend
    location /media/ {
        alias $PROJECT_PATH/media/;
        expires 1y;
        add_header Cache-Control "public";
    }
    
    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
}
EOF

        if [ $? -ne 0 ]; then
            print_error "Failed to create frontend Nginx configuration"
            exit 1
        fi
        
        print_status "Setting frontend directory permissions..."
        sudo chown -R ubuntu:www-data "$FRONTEND_PATH/dist"
        sudo chmod -R 755 "$FRONTEND_PATH/dist"
        
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
        if ! sudo certbot --nginx -d $FRONTEND_DOMAIN --non-interactive --agree-tos --email admin@$FRONTEND_DOMAIN; then
            print_warning "Frontend SSL certificate installation failed. You can set it up manually later."
            print_warning "Command: sudo certbot --nginx -d $FRONTEND_DOMAIN"
        fi
        
        print_header "Verifying Frontend Deployment"
        
        print_status "Testing frontend endpoint..."
        if curl -s -o /dev/null -w "%{http_code}" "http://$FRONTEND_DOMAIN/" | grep -q "200\|301\|302"; then
            print_status "✓ Frontend is responding"
        else
            print_warning "⚠ Frontend might not be responding correctly"
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
cat > deploy_update.sh << EOF
#!/bin/bash
# Auto-update deployment script

APP_NAME="$APP_NAME"
PROJECT_PATH="$PROJECT_PATH"

cd "\$PROJECT_PATH"

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
sudo systemctl restart gunicorn-\$APP_NAME.service

echo "Backend deployment update completed!"

# Update frontend if deployed
if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo ""
    echo "Frontend detected. To update frontend:"
    echo "1. Rebuild your React app (npm run build)"
    echo "2. Upload the new dist folder to: $FRONTEND_PATH/"
    echo "3. Set permissions: sudo chown -R ubuntu:www-data $FRONTEND_PATH/dist && sudo chmod -R 755 $FRONTEND_PATH/dist"
fi
EOF

chmod +x deploy_update.sh

print_status "Creating log monitoring script..."
cat > monitor_logs.sh << EOF
#!/bin/bash
# Log monitoring script for $APP_NAME

echo "=== $APP_NAME Log Monitor ==="
echo "Press Ctrl+C to stop"
echo "=========================="

# Monitor Gunicorn access logs with color coding
tail -f /var/log/gunicorn/$APP_NAME-access.log | while read line; do
    timestamp=\$(echo "\$line" | awk '{print \$1, \$2}')
    request=\$(echo "\$line" | grep -o '"[^"]*"' | head -1)
    status=\$(echo "\$line" | awk '{print \$9}')
    
    # Color code based on status
    if [[ \$status =~ ^2 ]]; then
        color="\033[32m"  # Green for 2xx
    elif [[ \$status =~ ^3 ]]; then
        color="\033[33m"  # Yellow for 3xx
    elif [[ \$status =~ ^4 ]]; then
        color="\033[31m"  # Red for 4xx
    elif [[ \$status =~ ^5 ]]; then
        color="\033[35m"  # Magenta for 5xx
    else
        color="\033[0m"   # Default
    fi
    
    echo -e "\${color}[\$timestamp] \$status \$request\033[0m"
done
EOF

chmod +x monitor_logs.sh

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
echo "   • Domain: http://$DOMAIN_NAME (https after SSL setup)"
echo "   • Project Path: $PROJECT_PATH"
echo "   • Database: $DB_NAME"
echo "   • Swagger Docs: http://$DOMAIN_NAME/yele-docs/"
echo ""

if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo "📋 Frontend Deployment Summary:"
    echo "   • Frontend Domain: http://$FRONTEND_DOMAIN (https after SSL setup)"
    echo "   • Frontend Path: $FRONTEND_PATH/dist"
    echo "   • Frontend Config: $FRONTEND_APP_NAME"
    echo ""
fi

echo "🔧 Service Management Commands:"
echo "   • Restart Backend: sudo systemctl restart gunicorn-$APP_NAME.service"
echo "   • View Backend Logs: sudo journalctl -u gunicorn-$APP_NAME.service -f"
echo "   • Monitor Requests: ./monitor_logs.sh"
echo "   • Update Deployment: ./deploy_update.sh"
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
echo "   • Backend API: http://$DOMAIN_NAME"
echo "   • Admin Panel: http://$DOMAIN_NAME/admin/"
echo "   • Swagger Docs: http://$DOMAIN_NAME/yele-docs/"

if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo "   • Frontend App: http://$FRONTEND_DOMAIN"
fi

echo ""
echo "📝 Next Steps:"
echo "   1. Create Django superuser: python manage.py createsuperuser"
echo "   2. Update your .env file with actual API keys"
echo "   3. Test all endpoints and frontend functionality"
echo "   4. Set up SSL certificates if they failed"

if [ "$FRONTEND_DEPLOYED" = true ]; then
    echo "   5. Test API connectivity from frontend"
    echo "   6. Verify React routing works correctly"
fi

echo ""

print_warning "Remember to:"
print_warning "• Update your .env file with production API keys"
print_warning "• Create a Django superuser account"
print_warning "• Set up regular database backups"
print_warning "• Monitor application logs regularly"

if [ "$FRONTEND_DEPLOYED" = true ]; then
    print_warning "• Test frontend-backend API connectivity"
    print_warning "• Verify all React routes work correctly"
fi

echo ""
print_status "Deployment script completed successfully! 🚀"
