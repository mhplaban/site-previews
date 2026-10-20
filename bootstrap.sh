#!/bin/bash
# Brainiac Biz business server bootstrap - Contabo VPS 167.86.110.205
# Run as root. Idempotent-ish: safe to re-run.
set -x
exec > >(tee -a /root/bootstrap.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

# 1. Updates
apt-get update
apt-get upgrade -y

# 2. Core stack: nginx + PHP-FPM + MariaDB + certbot + tools
apt-get install -y nginx php-fpm php-cli php-mysql php-xml php-mbstring php-curl php-zip php-gd php-intl php-bcmath mariadb-server certbot python3-certbot-nginx ufw git unzip curl fail2ban

# 3. Firewall (VNC console stays available as fallback)
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 4. SSH key for Rio (key auth alongside password)
mkdir -p /root/.ssh && chmod 700 /root/.ssh
grep -q 'hatch' /root/.ssh/authorized_keys 2>/dev/null || echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDTDOB/usthzODeagx4od0XIy84o+2lFxaKi77l9NMCS hatch' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# 5. Services on
systemctl enable --now nginx
systemctl enable --now mariadb
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
systemctl enable --now php${PHPV}-fpm

# 6. WordPress for brainiacbiz.com (Hasan's call 2026-10-20)
# Database + user with a generated password that never leaves this server.
DBNAME=brainiacbiz_wp
DBUSER=brainiacbiz
DBPASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 28)
mysql -e "CREATE DATABASE IF NOT EXISTS ${DBNAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${DBUSER}'@'localhost'; FLUSH PRIVILEGES;"

# WP-CLI
if [ ! -x /usr/local/bin/wp ]; then
  curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp
  chmod +x /usr/local/bin/wp
fi

# Core files
mkdir -p /var/www/brainiacbiz.com
cd /var/www/brainiacbiz.com
if [ ! -f wp-config.php ]; then
  sudo -u www-data /usr/local/bin/wp core download --path=/var/www/brainiacbiz.com --force
  sudo -u www-data /usr/local/bin/wp config create --path=/var/www/brainiacbiz.com --dbname="${DBNAME}" --dbuser="${DBUSER}" --dbpass="${DBPASS}" --dbhost=localhost
fi
chown -R www-data:www-data /var/www/brainiacbiz.com
find /var/www/brainiacbiz.com -type d -exec chmod 755 {} \;
find /var/www/brainiacbiz.com -type f -exec chmod 644 {} \;
# WordPress core install (admin user/password) is completed afterwards
# through the web install wizard so Hasan sets his own admin credentials.

# 7. nginx vhost
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
cat > /etc/nginx/sites-available/brainiacbiz.com <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name brainiacbiz.com www.brainiacbiz.com;
    root /var/www/brainiacbiz.com;
    index index.html index.php;
    location / { try_files \$uri \$uri/ /index.php?\$args; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHPV}-fpm.sock;
    }
    location ~ /\.ht { deny all; }
}
NGINX
ln -sf /etc/nginx/sites-available/brainiacbiz.com /etc/nginx/sites-enabled/brainiacbiz.com
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 8. Done marker
{
  echo "BOOTSTRAP_DONE $(date -u +%FT%TZ)"
  nginx -v 2>&1
  php -v | head -1
  mysql --version
} > /root/bootstrap-done.txt
echo "=== BOOTSTRAP COMPLETE ==="
