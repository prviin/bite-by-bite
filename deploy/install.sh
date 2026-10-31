#!/usr/bin/env bash
# Run on a fresh Ubuntu Droplet after source and a private data snapshot arrive.
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this installer as root on the Droplet.' >&2
  exit 1
fi
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_root"
if [ ! -s deploy/.env ] || [ ! -s data/accounts.sqlite ] || [ ! -s data/encryption.key ]; then
  echo 'First add deploy/.env with APP_DOMAIN and transfer your private migration snapshot into data/.' >&2
  exit 1
fi
if ! sed -n 's/^APP_DOMAIN=//p' deploy/.env | grep -Eq '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$'; then
  echo 'APP_DOMAIN must be a bare public DNS hostname.' >&2
  exit 1
fi
apt-get update
apt-get install -y docker.io docker-compose-v2 ufw
systemctl enable --now docker
mkdir -p backups
chown -R 1000:1000 data backups
chmod 700 data backups
find data -type f -exec chmod 600 {} +
docker compose --env-file deploy/.env -f deploy/compose.yaml config --quiet
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d --build
cat > /etc/systemd/system/bite-backup.service <<EOF
[Unit]
Description=Back up the private Bite by Bite journal
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=$task_root
ExecStart=/usr/bin/docker compose --env-file deploy/.env -f deploy/compose.yaml exec -T app node scripts/backup.mjs /app/data /backups
EOF
cat > /etc/systemd/system/bite-backup.timer <<'EOF'
[Unit]
Description=Daily Bite by Bite backup

[Timer]
OnCalendar=*-*-* 03:00:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now bite-backup.timer
docker compose --env-file deploy/.env -f deploy/compose.yaml ps
echo 'Deployment started. Verify HTTPS and sign-in before relying on the phone app.'
