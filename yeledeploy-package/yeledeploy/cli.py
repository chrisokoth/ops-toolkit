#!/usr/bin/env python3
"""
YeleDeploy - Django EC2 Auto Deployment Tool
"""

import click
import os
import sys
import subprocess
import psycopg2
from psycopg2 import sql
from colorama import init, Fore, Style
try:
    from .deployment import DjangoDeployer
    from .database import DatabaseManager
    from .utils import print_status, print_error, print_warning, print_header
except ImportError:
    # Fallback for development
    from deployment import DjangoDeployer
    from database import DatabaseManager
    from utils import print_status, print_error, print_warning, print_header

# Initialize colorama
init(autoreset=True)

@click.command()
@click.option('--app-name', prompt='App name', help='Application name for services')
@click.option('--domain', prompt='Domain name', help='Domain name (e.g., api.example.com)')
@click.option('--project-dir', prompt='Project directory', help='Django project directory name')
@click.option('--django-project', prompt='Django project module', help='Django project module name')
@click.option('--db-name', prompt='Database name', help='PostgreSQL database name')
@click.option('--db-password', prompt='Database password', hide_input=True, help='PostgreSQL password')
@click.option('--env-file', type=click.Path(exists=True), help='Path to .env file')
@click.option('--skip-cleanup', is_flag=True, help='Skip cleanup on failure')
def deploy(app_name, domain, project_dir, django_project, db_name, db_password, env_file, skip_cleanup):
    """Deploy Django application to EC2 with PostgreSQL, Nginx, and Gunicorn"""
    
    print_header("YeleDeploy - Django EC2 Auto Deployment")
    
    # Initialize deployer
    deployer = DjangoDeployer(
        app_name=app_name,
        domain=domain,
        project_dir=project_dir,
        django_project=django_project,
        db_name=db_name,
        db_password=db_password,
        env_file=env_file,
        skip_cleanup=skip_cleanup
    )
    
    try:
        # Run deployment
        deployer.deploy()
        print_header("Deployment Complete!")
        deployer.print_summary()
    except Exception as e:
        print_error(f"Deployment failed: {str(e)}")
        if not skip_cleanup:
            deployer.cleanup()
        sys.exit(1)

@click.command()
@click.option('--app-name', required=True, help='Application name')
def update(app_name):
    """Update existing deployment"""
    print_header("Updating Deployment")
    
    project_path = f"/home/ubuntu/{app_name}"
    if not os.path.exists(project_path):
        print_error(f"Project directory {project_path} not found")
        sys.exit(1)
    
    try:
        os.chdir(project_path)
        
        # Pull latest changes
        print_status("Pulling latest changes...")
        subprocess.run(["git", "pull", "origin", "main"], check=True)
        
        # Activate venv and update dependencies
        print_status("Updating dependencies...")
        subprocess.run(["./venv/bin/pip", "install", "-r", "requirements.txt"], check=True)
        
        # Run migrations
        print_status("Running migrations...")
        subprocess.run(["./venv/bin/python", "manage.py", "migrate"], check=True)
        
        # Collect static files
        print_status("Collecting static files...")
        subprocess.run(["./venv/bin/python", "manage.py", "collectstatic", "--noinput"], check=True)
        
        # Restart service
        print_status("Restarting Gunicorn service...")
        subprocess.run(["sudo", "systemctl", "restart", f"gunicorn-{app_name}.service"], check=True)
        
        print_status("Update completed successfully!")
        
    except subprocess.CalledProcessError as e:
        print_error(f"Update failed: {str(e)}")
        sys.exit(1)

@click.command()
@click.option('--app-name', required=True, help='Application name')
def logs(app_name):
    """Monitor application logs"""
    print_header(f"Monitoring logs for {app_name}")
    
    try:
        subprocess.run([
            "sudo", "journalctl", 
            "-u", f"gunicorn-{app_name}.service", 
            "-f", "--lines=50"
        ])
    except KeyboardInterrupt:
        print_status("Log monitoring stopped")

@click.group()
def main():
    """YeleDeploy - Django EC2 Auto Deployment Tool"""
    pass

main.add_command(deploy)
main.add_command(update)
main.add_command(logs)

if __name__ == '__main__':
    main()