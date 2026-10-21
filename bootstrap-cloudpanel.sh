#!/bin/bash
# CloudPanel Community Edition install - Brainiac Biz VPS (Contabo Cloud VPS 4)
# Run as root (via Contabo reinstall cloud-init). Takes 5-15 minutes.
set -x
exec > >(tee -a /root/cloudpanel-bootstrap.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

# 1. Base updates
apt-get update
apt-get upgrade -y
apt-get install -y curl wget sudo

# 2. CloudPanel CE v2 (official installer, HTTPS; MariaDB 10.11 engine)
curl -sS https://installer.cloudpanel.io/ce/v2/install.sh -o /root/cloudpanel-install.sh
DB_ENGINE=MARIADB_10.11 bash /root/cloudpanel-install.sh

# 3. Done marker (panel admin user is created afterwards in the web UI)
echo "CLOUDPANEL_INSTALL_DONE $(date -u +%FT%TZ)" > /root/cloudpanel-done.txt
echo "Panel: https://$(hostname -I | awk '{print $1}'):8443" >> /root/cloudpanel-done.txt
echo "=== CLOUDPANEL INSTALL COMPLETE ==="
