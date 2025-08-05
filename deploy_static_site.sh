#!/bin/bash

set -e

echo "🔧 === Vite Static Site Deployment Script ==="

# Prompt for domain and nginx config name
read -p "Enter your domain name (e.g., bontuteur.com): " DOMAIN
read -p "Enter the Nginx config name (e.g., bontuteur): " CONFIG_NAME
read -p "Enter the directory where your Vite project lives (e.g., bontuter-web): " PROJECT_DIR

# Build paths
DIST_SRC="$HOME/$PROJECT_DIR/dist"
WWW_DIR="/var/www/$DOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$CONFIG_NAME"

# Display paths
echo "🌐 Domain: $DOMAIN"
echo "📁 Vite project directory: $PROJECT_DIR"
echo "📂 Dist source: $DIST_SRC"
echo "📂 Web root: $WWW_DIR"
echo "⚙️  Nginx config: $NGINX_CONF"

# Check if dist exists
if [ ! -d "$DIST_SRC" ]; then
    echo "❌ Error: $DIST_SRC does not exist. Make sure you've built your project with 'npm run build'."
    exit 1
fi

# Install nginx and certbot
echo "📦 Installing Nginx and Certbot (if needed)..."
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx curl

# Create target web directory
echo "📁 Creating $WWW_DIR..."
sudo mkdir -p $WWW_DIR

# Copy built files
echo "📤 Copying files from $DIST_SRC to $WWW_DIR"
sudo cp -r $DIST_SRC/* $WWW_DIR

# Create nginx config
echo "📝 Creating Nginx config..."
sudo bash -c "cat > $NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    root $WWW_DIR;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|otf|eot|json|txt)$ {
        expires 1y;
        access_log off;
        add_header Cache-Control "public";
    }
}
EOF

# Enable nginx config
echo "🔗 Enabling site..."
sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Set up SSL
echo "🔐 Getting SSL certificate with Certbot..."
sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

# === Verification function ===
verify_site() {
    echo "🔍 Verifying deployment by checking https://$DOMAIN..."

    for i in {1..5}; do
        sleep 2
        echo "⏳ Attempt $i..."
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN)

        if [ "$RESPONSE" == "200" ]; then
            echo "✅ Site is live and returning HTTP 200!"
            return 0
        fi
    done

    echo "❌ Site did not respond successfully after 5 tries."
    return 1
}

# Run verification
if verify_site; then
    echo "🎉 Deployment verified successfully at: https://$DOMAIN"
else
    echo "⚠️ Deployment failed. Rolling back..."
    if [ -f "./reset_static_site.sh" ]; then
        bash ./reset_static_site.sh <<< "$DOMAIN"$'\n'"$CONFIG_NAME"$'\n'y
    else
        echo "⚠️ Cleanup script not found! Please run reset_static_site.sh manually to clean up."
    fi
    exit 1
fi
