"""
Main deployment module for YeleDeploy
"""

import os
import subprocess
import shutil
from jinja2 import Template
from .database import DatabaseManager
from .utils import (
    print_status, print_error, print_warning, print_header,
    run_command, create_directory, generate_secret_key,
    validate_domain, get_project_path, get_venv_path
)

class DjangoDeployer:
    def __init__(self, app_name, domain, project_dir, django_project, 
                 db_name, db_password, env_file=None, skip_cleanup=False):
        self.app_name = app_name
        self.domain = domain
        self.project_dir = project_dir
        self.django_project = django_project
        self.db_name = db_name
        self.db_password = db_password
        self.env_file = env_file
        self.skip_cleanup = skip_cleanup
        
        # Paths
        self.project_path = get_project_path(project_dir)
        self.venv_path = get_venv_path(self.project_path)
        
        # Database manager
        self.db_manager = DatabaseManager(db_name, db_password)
        
        # Validate inputs
        validate_domain(domain)
    
    def install_system_dependencies(self):
        """Install required system packages"""
        print_header("Installing System Dependencies")
        
        print_status("Updating system packages...")
        run_command(["sudo", "apt", "update"])
        run_command(["sudo", "apt", "upgrade", "-y"])
        
        print_status("Installing Python and development tools...")
        packages = [
            "python3", "python3-pip", "python3-venv", "python3-dev",
            "build-essential", "libssl-dev", "libffi-dev", "libpq-dev",
            "libjpeg-dev", "zlib1g-dev"
        ]
        run_command(["sudo", "apt", "install", "-y"] + packages)
        
        print_status("Installing server components...")
        server_packages = [
            "postgresql", "postgresql-contrib", "nginx", "git",
            "curl", "wget", "ccze", "multitail"
        ]
        run_command(["sudo", "apt", "install", "-y"] + server_packages)
    
    def setup_python_environment(self):
        """Setup Python virtual environment"""
        print_header("Setting up Python Environment")
        
        if not os.path.exists(self.project_path):
            raise Exception(f"Project directory {self.project_path} not found")
        
        os.chdir(self.project_path)
        
        print_status("Creating virtual environment...")
        run_command(["python3", "-m", "venv", "venv"])
        
        print_status("Upgrading pip and installing dependencies...")
        run_command([f"{self.venv_path}/bin/pip", "install", "--upgrade", "pip"])
        run_command([f"{self.venv_path}/bin/pip", "install", "-r", "requirements.txt"])
        run_command([f"{self.venv_path}/bin/pip", "install", "gunicorn", "psycopg2-binary"])
    
    def create_env_file(self):
        """Create .env file with configuration"""
        print_status("Creating .env file...")
        
        secret_key = generate_secret_key()
        
        env_content = f"""# Generated Django Secret Key
SECRET_KEY={secret_key}

# Database Configuration
DB_NAME={self.db_name}
DB_USER=postgres
DB_PASSWORD={self.db_password}
DB_HOST=localhost
DB_PORT=5432

# Django Settings
DEBUG=False
ALLOWED_HOSTS={self.domain},localhost,127.0.0.1

# Static files configuration
STATIC_URL=/static/
STATIC_ROOT=/home/ubuntu/{self.project_dir}/staticfiles/
MEDIA_URL=/media/
MEDIA_ROOT=/home/ubuntu/{self.project_dir}/media/

# Swagger/API Documentation
USE_SWAGGER=True
SWAGGER_SETTINGS={{
    'SECURITY_DEFINITIONS': {{
        'Basic': {{
            'type': 'basic'
        }},
        'Bearer': {{
            'type': 'apiKey',
            'name': 'Authorization',
            'in': 'header'
        }}
    }}
}}
"""
        
        # If user provided env file, append its content
        if self.env_file and os.path.exists(self.env_file):
            with open(self.env_file, 'r') as f:
                user_env = f.read()
            env_content += f"\n# User provided environment variables\n{user_env}"
        
        with open(f"{self.project_path}/.env", "w") as f:
            f.write(env_content)
    
    def setup_django(self):
        """Setup Django application"""
        print_header("Configuring Django Application")
        
        self.create_env_file()
        
        print_status("Running Django migrations...")
        os.chdir(self.project_path)
        run_command([f"{self.venv_path}/bin/python", "manage.py", "migrate"])
        
        print_status("Collecting static files...")
        # Ensure static files directory exists
        static_dir = f"{self.project_path}/staticfiles"
        os.makedirs(static_dir, exist_ok=True)
        
        run_command([f"{self.venv_path}/bin/python", "manage.py", "collectstatic", "--noinput"])
        
        # Ensure media directory exists
        media_dir = f"{self.project_path}/media"
        os.makedirs(media_dir, exist_ok=True)
    
    def setup_gunicorn(self):
        """Setup Gunicorn service"""
        print_header("Configuring Gunicorn")
        
        # Create Gunicorn configuration
        gunicorn_config = f"""# Gunicorn configuration for {self.app_name}
bind = "unix:/run/gunicorn/gunicorn-{self.app_name}.sock"
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
errorlog = "/var/log/gunicorn/{self.app_name}-error.log"
accesslog = "/var/log/gunicorn/{self.app_name}-access.log"
loglevel = "info"
"""
        
        with open(f"{self.project_path}/gunicorn.conf.py", "w") as f:
            f.write(gunicorn_config)
        
        # Create log directories
        print_status("Creating log directories...")
        run_command(["sudo", "mkdir", "-p", "/var/log/gunicorn"])
        run_command(["sudo", "chown", "ubuntu:ubuntu", "/var/log/gunicorn"])
        run_command(["sudo", "mkdir", "-p", "/run/gunicorn"])
        run_command(["sudo", "chown", "ubuntu:www-data", "/run/gunicorn"])
        run_command(["sudo", "chmod", "755", "/run/gunicorn"])
        
        # Create systemd service
        print_status("Creating systemd service for Gunicorn...")
        service_content = f"""[Unit]
Description=Gunicorn instance to serve {self.app_name}
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory={self.project_path}
Environment="PATH={self.venv_path}/bin"
Environment="DJANGO_SETTINGS_MODULE={self.django_project}.settings"
ExecStart={self.venv_path}/bin/gunicorn --config {self.project_path}/gunicorn.conf.py {self.django_project}.wsgi:application
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
"""
        
        with open(f"/tmp/gunicorn-{self.app_name}.service", "w") as f:
            f.write(service_content)
        
        run_command(["sudo", "mv", f"/tmp/gunicorn-{self.app_name}.service", 
                    f"/etc/systemd/system/gunicorn-{self.app_name}.service"])
        
        # Create tmpfiles configuration
        tmpfiles_content = f"d /run/gunicorn 0755 ubuntu www-data -\n"
        with open(f"/tmp/gunicorn-{self.app_name}.conf", "w") as f:
            f.write(tmpfiles_content)
        
        run_command(["sudo", "mv", f"/tmp/gunicorn-{self.app_name}.conf", 
                    f"/etc/tmpfiles.d/gunicorn-{self.app_name}.conf"])
        
        run_command(["sudo", "systemd-tmpfiles", "--create"])
    
    def setup_nginx(self):
        """Setup Nginx configuration"""
        print_header("Configuring Nginx")
        
        print_status("Removing default Nginx configuration...")
        run_command(["sudo", "rm", "-f", "/etc/nginx/sites-enabled/default"])
        
        print_status(f"Creating Nginx configuration for {self.app_name}...")
        nginx_config = f"""# HTTP Server
server {{
    listen 80;
    server_name {self.domain};
    
    # Logging
    access_log /var/log/nginx/{self.app_name}.access.log;
    error_log /var/log/nginx/{self.app_name}.error.log;
    
    # Main application
    location / {{
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-{self.app_name}.sock;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
    }}
    
    # Static files (including Swagger assets)
    location /static/ {{
        alias {self.project_path}/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        
        # Special handling for Swagger documentation assets
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {{
            expires 1y;
            add_header Cache-Control "public, immutable";
        }}
    }}
    
    # Media files
    location /media/ {{
        alias {self.project_path}/media/;
        expires 1y;
        add_header Cache-Control "public";
    }}
    
    # API documentation endpoints
    location /docs/ {{
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-{self.app_name}.sock;
    }}
    
    location /swagger/ {{
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-{self.app_name}.sock;
    }}
    
    location /redoc/ {{
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://unix:/run/gunicorn/gunicorn-{self.app_name}.sock;
    }}
}}
"""
        
        with open(f"/tmp/{self.app_name}", "w") as f:
            f.write(nginx_config)
        
        run_command(["sudo", "mv", f"/tmp/{self.app_name}", f"/etc/nginx/sites-available/{self.app_name}"])
        run_command(["sudo", "ln", "-sf", f"/etc/nginx/sites-available/{self.app_name}", 
                    f"/etc/nginx/sites-enabled/"])
        
        print_status("Testing Nginx configuration...")
        run_command(["sudo", "nginx", "-t"])
    
    def setup_ssl(self):
        """Setup SSL certificate with Certbot"""
        print_header("Setting up SSL Certificate")
        
        print_status("Installing Certbot...")
        run_command(["sudo", "apt", "install", "-y", "certbot", "python3-certbot-nginx"])
        
        print_status(f"Obtaining SSL certificate for {self.domain}...")
        try:
            run_command([
                "sudo", "certbot", "--nginx", "-d", self.domain,
                "--non-interactive", "--agree-tos", "--email", f"admin@{self.domain}"
            ])
            
            # Setup auto-renewal
            print_status("Setting up SSL certificate auto-renewal...")
            cron_job = "0 12 * * * /usr/bin/certbot renew --quiet"
            run_command(f'(sudo crontab -l 2>/dev/null; echo "{cron_job}") | sudo crontab -', shell=True)
            
        except Exception:
            print_warning("SSL certificate installation failed. You can set it up manually later.")
            print_warning(f"Command: sudo certbot --nginx -d {self.domain}")
    
    def setup_security(self):
        """Setup security and permissions"""
        print_header("Setting up Security and Permissions")
        
        print_status("Setting file permissions...")
        run_command(["sudo", "chown", "-R", "ubuntu:ubuntu", self.project_path])
        run_command(["sudo", "chmod", "-R", "755", self.project_path])
        run_command(["sudo", "chmod", "644", f"{self.project_path}/.env"])
        
        # Add ubuntu to www-data group
        run_command(["sudo", "usermod", "-a", "-G", "www-data", "ubuntu"])
        
        print_status("Configuring firewall...")
        run_command(["sudo", "ufw", "allow", "OpenSSH"])
        run_command(["sudo", "ufw", "allow", "Nginx Full"])
        run_command(["sudo", "ufw", "--force", "enable"])
    
    def start_services(self):
        """Start all services"""
        print_header("Starting Services")
        
        print_status("Reloading systemd daemon...")
        run_command(["sudo", "systemctl", "daemon-reload"])
        
        print_status("Starting Gunicorn service...")
        run_command(["sudo", "systemctl", "start", f"gunicorn-{self.app_name}.service"])
        run_command(["sudo", "systemctl", "enable", f"gunicorn-{self.app_name}.service"])
        
        print_status("Starting Nginx...")
        run_command(["sudo", "systemctl", "start", "nginx"])
        run_command(["sudo", "systemctl", "enable", "nginx"])
    
    def create_utility_scripts(self):
        """Create deployment utility scripts"""
        print_header("Creating Deployment Utilities")
        
        # Update script
        print_status("Creating deployment update script...")
        update_script = f"""#!/bin/bash
# Auto-update deployment script

APP_NAME="{self.app_name}"
PROJECT_PATH="{self.project_path}"

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

echo "Deployment update completed!"
"""
        
        with open(f"{self.project_path}/deploy_update.sh", "w") as f:
            f.write(update_script)
        run_command(["chmod", "+x", f"{self.project_path}/deploy_update.sh"])
        
        # Log monitoring script
        print_status("Creating log monitoring script...")
        monitor_script = f"""#!/bin/bash
# Log monitoring script for {self.app_name}

echo "=== {self.app_name} Log Monitor ==="
echo "Press Ctrl+C to stop"
echo "=========================="

# Monitor Gunicorn access logs with color coding
tail -f /var/log/gunicorn/{self.app_name}-access.log | while read line; do
    timestamp=$(echo "$line" | awk '{{print $1, $2}}')
    request=$(echo "$line" | grep -o '"[^"]*"' | head -1)
    status=$(echo "$line" | awk '{{print $9}}')
    
    # Color code based on status
    if [[ $status =~ ^2 ]]; then
        color="\\033[32m"  # Green for 2xx
    elif [[ $status =~ ^3 ]]; then
        color="\\033[33m"  # Yellow for 3xx
    elif [[ $status =~ ^4 ]]; then
        color="\\033[31m"  # Red for 4xx
    elif [[ $status =~ ^5 ]]; then
        color="\\033[35m"  # Magenta for 5xx
    else
        color="\\033[0m"   # Default
    fi
    
    echo -e "${{color}}[$timestamp] $status $request\\033[0m"
done
"""
        
        with open(f"{self.project_path}/monitor_logs.sh", "w") as f:
            f.write(monitor_script)
        run_command(["chmod", "+x", f"{self.project_path}/monitor_logs.sh"])
    
    def verify_deployment(self):
        """Verify deployment status"""
        print_header("Verifying Deployment")
        
        print_status("Checking service statuses...")
        
        # Check Gunicorn
        try:
            result = run_command([
                "sudo", "systemctl", "is-active", f"gunicorn-{self.app_name}.service"
            ], capture_output=True, text=True)
            if result.stdout.strip() == "active":
                print_status("✓ Gunicorn service is running")
            else:
                print_error("✗ Gunicorn service failed to start")
        except:
            print_error("✗ Gunicorn service failed to start")
        
        # Check Nginx
        try:
            result = run_command([
                "sudo", "systemctl", "is-active", "nginx"
            ], capture_output=True, text=True)
            if result.stdout.strip() == "active":
                print_status("✓ Nginx service is running")
            else:
                print_error("✗ Nginx service failed to start")
        except:
            print_error("✗ Nginx service failed to start")
        
        # Check PostgreSQL
        try:
            result = run_command([
                "sudo", "systemctl", "is-active", "postgresql"
            ], capture_output=True, text=True)
            if result.stdout.strip() == "active":
                print_status("✓ PostgreSQL service is running")
            else:
                print_error("✗ PostgreSQL service failed to start")
        except:
            print_error("✗ PostgreSQL service failed to start")
        
        # Check socket file
        if os.path.exists(f"/run/gunicorn/gunicorn-{self.app_name}.sock"):
            print_status("✓ Gunicorn socket created successfully")
        else:
            print_warning("⚠ Gunicorn socket not found")
        
        # Test application endpoint
        print_status("Testing application endpoint...")
        try:
            result = run_command([
                "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", 
                f"http://{self.domain}/"
            ], capture_output=True, text=True)
            
            if result.stdout.strip() in ["200", "301", "302"]:
                print_status("✓ Application is responding")
            else:
                print_warning("⚠ Application might not be responding correctly")
        except:
            print_warning("⚠ Could not test application endpoint")
    
    def cleanup(self):
        """Cleanup deployment on failure"""
        if self.skip_cleanup:
            return
            
        print_header("Cleaning up failed deployment...")
        
        try:
            # Stop and remove services
            print_status("Stopping and removing services...")
            run_command(["sudo", "systemctl", "stop", f"gunicorn-{self.app_name}.service"], check=False)
            run_command(["sudo", "systemctl", "disable", f"gunicorn-{self.app_name}.service"], check=False)
            
            run_command(["sudo", "rm", "-f", f"/etc/systemd/system/gunicorn-{self.app_name}.service"], check=False)
            run_command(["sudo", "rm", "-f", f"/etc/tmpfiles.d/gunicorn-{self.app_name}.conf"], check=False)
            
            # Remove nginx configuration
            run_command(["sudo", "rm", "-f", f"/etc/nginx/sites-available/{self.app_name}"], check=False)
            run_command(["sudo", "rm", "-f", f"/etc/nginx/sites-enabled/{self.app_name}"], check=False)
            
            # Remove log directories
            run_command(["sudo", "rm", "-rf", f"/var/log/gunicorn/{self.app_name}-*"], check=False)
            run_command(["sudo", "rm", "-rf", f"/var/log/nginx/{self.app_name}.*"], check=False)
            
            # Remove socket directory
            run_command(["sudo", "rm", "-rf", "/run/gunicorn"], check=False)
            
            # Remove virtual environment
            if os.path.exists(f"{self.project_path}/venv"):
                print_status("Removing virtual environment...")
                shutil.rmtree(f"{self.project_path}/venv")
            
            # Remove generated files
            files_to_remove = [
                f"{self.project_path}/.env",
                f"{self.project_path}/gunicorn.conf.py",
                f"{self.project_path}/deploy_update.sh",
                f"{self.project_path}/monitor_logs.sh"
            ]
            
            for file_path in files_to_remove:
                if os.path.exists(file_path):
                    os.remove(file_path)
            
            run_command(["sudo", "systemctl", "daemon-reload"], check=False)
            print_status("Cleanup completed. You can now run the deployment again.")
            
        except Exception as e:
            print_error(f"Cleanup failed: {e}")
    
    def print_summary(self):
        """Print deployment summary"""
        print("")
        print("🎉 Your Django application has been successfully deployed!")
        print("")
        print("📋 Deployment Summary:")
        print(f"   • App Name: {self.app_name}")
        print(f"   • Domain: http://{self.domain} (https after SSL setup)")
        print(f"   • Project Path: {self.project_path}")
        print(f"   • Database: {self.db_name}")
        print("")
        print("🔧 Service Management Commands:")
        print(f"   • Restart App: sudo systemctl restart gunicorn-{self.app_name}.service")
        print(f"   • View Logs: sudo journalctl -u gunicorn-{self.app_name}.service -f")
        print("   • Monitor Requests: ./monitor_logs.sh")
        print("   • Update Deployment: ./deploy_update.sh")
        print("")
        print("📁 Important Files Created:")
        print(f"   • Gunicorn Service: /etc/systemd/system/gunicorn-{self.app_name}.service")
        print(f"   • Nginx Config: /etc/nginx/sites-available/{self.app_name}")
        print(f"   • App Logs: /var/log/gunicorn/{self.app_name}-*.log")
        print(f"   • Nginx Logs: /var/log/nginx/{self.app_name}.*.log")
        print("")
        print("🔗 Quick Tests:")
        print(f"   • Visit: http://{self.domain}")
        print(f"   • Admin: http://{self.domain}/admin/")
        print(f"   • API Docs: http://{self.domain}/docs/ (if available)")
        print(f"   • Swagger: http://{self.domain}/swagger/ (if available)")
        print("")
        print("📝 Next Steps:")
        print("   1. Create Django superuser: python manage.py createsuperuser")
        print("   2. Update your .env file with actual API keys")
        print("   3. Test all endpoints including Swagger documentation")
        print("   4. Set up SSL certificate if it failed")
        print("")
        print_warning("Remember to:")
        print_warning("• Update your .env file with production API keys")
        print_warning("• Create a Django superuser account")
        print_warning("• Set up regular database backups")
        print_warning("• Monitor application logs regularly")
        print("")
        print_status("Deployment completed successfully! 🚀")
    
    def deploy(self):
        """Main deployment function"""
        try:
            self.install_system_dependencies()
            self.db_manager.setup()
            self.setup_python_environment()
            self.setup_django()
            self.setup_gunicorn()
            self.setup_nginx()
            self.setup_ssl()
            self.setup_security()
            self.start_services()
            self.create_utility_scripts()
            self.verify_deployment()
        except Exception as e:
            print_error(f"Deployment failed: {e}")
            raise