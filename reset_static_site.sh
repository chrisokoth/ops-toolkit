#!/bin/bash

set -e

echo "🧹 === Static Site Cleanup Script ==="

# Prompt for domain and config name
read -p "Enter the domain name to clean up (e.g., bontuteur.com): " DOMAIN
read -p "Enter the Nginx config name (e.g., bontuteur): " CONFIG_NAME

# Define paths
WWW_DIR="/var/www/$DOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$CONFIG_NAME"
NGINX_LINK="/etc/nginx/sites-enabled/$CONFIG_NAME"

echo "🗑️ Cleaning up deployment for: $DOMAIN"

# Remove website files
if [ -d "$WWW_DIR" ]; then
    echo "📁 Removing $WWW_DIR"
    sudo rm -rf "$WWW_DIR"
else
    echo "⚠️  Web root not found: $WWW_DIR"
fi

# Remove nginx config
if [ -f "$NGINX_CONF" ]; then
    echo "⚙️  Removing Nginx config: $NGINX_CONF"
    sudo rm -f "$NGINX_CONF"
fi

# Remove symlink
if [ -L "$NGINX_LINK" ]; then
    echo "🔗 Removing Nginx symlink: $NGINX_LINK"
    sudo rm -f "$NGINX_LINK"
fi

# Reload nginx
echo "🔄 Reloading Nginx..."
sudo nginx -t && sudo systemctl reload nginx

# Remove SSL certificate
read -p "❓ Do you also want to delete the SSL certificate for $DOMAIN? [y/N]: " DELETE_SSL
if [[ "$DELETE_SSL" == "y" || "$DELETE_SSL" == "Y" ]]; then
    echo "🔐 Deleting SSL certificate..."
    sudo certbot delete --cert-name $DOMAIN
fi

echo "✅ Clean-up complete for: $DOMAIN"
