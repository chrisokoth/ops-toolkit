# YeleDeploy

Automated Django deployment tool for EC2 with PostgreSQL, Nginx, and Gunicorn.

## Features

- **Safe Database Operations**: Only creates new databases, never drops existing ones
- **Swagger Documentation Support**: Properly configures static files for API documentation
- **Automated SSL Setup**: Configures HTTPS with Let's Encrypt
- **Service Management**: Sets up systemd services for reliable operation
- **Comprehensive Logging**: Structured logging with monitoring tools
- **Security Configuration**: Firewall setup and proper permissions

## Installation

```bash
pip install yeledeploy
```

## Usage

### Deploy a new application

```bash
yeledeploy deploy
```

This will prompt you for:
- App name (used for service naming)
- Domain name
- Project directory name
- Django project module name  
- Database name
- Database password

### Update existing deployment

```bash
yeledeploy update --app-name myapp
```

### Monitor logs

```bash
yeledeploy logs --app-name myapp
```

## Prerequisites

- Ubuntu EC2 instance with sudo access
- Git repository with Django project
- Domain name pointing to your EC2 instance

## Project Structure

Your Django project should be cloned to `/home/ubuntu/` and have:
- `requirements.txt` file
- Standard Django project structure with `manage.py`
- Proper Django settings configuration

## Database Handling

YeleDeploy safely handles databases by:
1. Checking if the specified database already exists
2. Only creating new databases if they don't exist
3. Never dropping or modifying existing databases
4. Supporting multiple databases on the same PostgreSQL instance

## Static Files & Swagger

The tool properly configures static file serving including:
- Django static files collection
- Swagger/OpenAPI documentation assets
- Media files handling
- Proper Nginx configuration for all static content

## Environment Variables

You can provide a `.env` file or the tool will create a basic template with:
- Database configuration
- Django settings
- Static/media file paths
- Swagger configuration

## Service Management

After deployment, manage your application with:

```bash
# Restart application
sudo systemctl restart gunicorn-<app-name>.service

# View logs
sudo journalctl -u gunicorn-<app-name>.service -f

# Check status
sudo systemctl status gunicorn-<app-name>.service
```

## File Locations

- **Project**: `/home/ubuntu/<project-dir>/`
- **Logs**: `/var/log/gunicorn/<app-name>-*.log`
- **Nginx Config**: `/etc/nginx/sites-available/<app-name>`
- **Service**: `/etc/systemd/system/gunicorn-<app-name>.service`

## Development

To install for development:

```bash
git clone <repository>
cd yeledeploy
pip install -e .
```

## License

MIT License