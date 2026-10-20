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

# 6. Webroot + placeholder for brainiacbiz.com
mkdir -p /var/www/brainiacbiz.com
cat > /var/www/brainiacbiz.com/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Brainiac Biz - Websites and Google Business Profile Optimization</title>
<meta name="description" content="Brainiac Biz builds affordable one-page websites and optimizes Google Business Profiles for local businesses in the Columbia Valley and beyond.">
<style>
body{font-family:system-ui,Arial,sans-serif;margin:0;background:#0f172a;color:#e2e8f0;display:flex;min-height:100vh;align-items:center;justify-content:center}
main{max-width:640px;padding:32px;text-align:center}
h1{font-size:2rem;margin:0 0 12px}
p{line-height:1.6;color:#94a3b8}
.badge{display:inline-block;border:1px solid #334155;border-radius:999px;padding:4px 12px;font-size:.85rem;color:#cbd5e1;margin-bottom:16px}
</style>
</head>
<body>
<main>
<div class="badge">Brainiac Biz</div>
<h1>Websites and Google Business Profile optimization for local businesses.</h1>
<p>Our full site is on its way. We build modern, mobile-friendly one-page websites and help local businesses get found on Google.</p>
<p>Based in Radium Hot Springs, BC. Serving the Columbia Valley and beyond.</p>
</main>
</body>
</html>
HTML
chown -R www-data:www-data /var/www/brainiacbiz.com

# 7. nginx vhost
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
cat > /etc/nginx/sites-available/brainiacbiz.com <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name brainiacbiz.com www.brainiacbiz.com;
    root /var/www/brainiacbiz.com;
    index index.html index.php;
    location / { try_files \$uri \$uri/ =404; }
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
