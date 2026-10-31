# DigitalOcean personal deployment

This deploys the existing Node app and SQLite database to one private-use Linux VM. It does not create cloud resources or assume promotional credits are active. Public HTTPS serves the login page; journals require sign-in and registration is closed. Use a trusted personal Droplet, not a shared hosting account.

## 1. Create the Droplet

In DigitalOcean, check Billing for the actual promotional balance, eligible services, and expiry date. A dashboard link does not establish that an offer is applied. Set a billing alert. Credits are not a permanent spending cap; paid billing may continue after exhaustion/expiry.

Choose **Create → Droplet → Ubuntu 24.04 LTS → Basic → Regular → 1 GB / 1 CPU / 25 GB**. The listed price checked on 31 October 2026 was **US$6/month**, or **US$72/year before taxes and extras**. Frankfurt is a reasonable European region. Name it `bite-by-bite` and authenticate with an SSH public key. No GPU, managed database, load balancer, or AI inference resource is needed.

Record the public IP. Configure a DigitalOcean Cloud Firewall allowing SSH TCP 22 only from your administrator IP and HTTP/HTTPS TCP 80/443 from the internet. Port 3000 must not be public. The installer also enables Ubuntu's firewall for standard SSH and HTTP/HTTPS; it is intended for a fresh Droplet using SSH port 22.

## 2. Choose the HTTPS address

Point the A record of a DNS hostname you control (for example `food.example.com`) to the Droplet IPv4 address. Do not add an AAAA record unless IPv6 is configured. Caddy provisions and renews public TLS certificates after DNS and ports are ready. A bare IP with Caddy’s default local certificate will not give phones a publicly trusted installable app.

## 3. Prepare and upload source

From this project, create a source-only archive. This excludes account data and credentials:

```sh
tar --exclude=deploy/.env -czf /tmp/bite-by-bite-source.tgz .dockerignore Dockerfile package.json server.mjs accounts.mjs chatgpt.mjs public scripts deploy
scp /tmp/bite-by-bite-source.tgz root@DROPLET_IP:/tmp/
ssh root@DROPLET_IP
mkdir -p /opt/bite-by-bite
tar -xzf /tmp/bite-by-bite-source.tgz -C /opt/bite-by-bite
cd /opt/bite-by-bite
cp deploy/.env.example deploy/.env
nano deploy/.env
```

Set `APP_DOMAIN` to the DNS hostname, without `https://` or a path. The archive must not contain `deploy/.env` if it has been customized; add `--exclude=deploy/.env` when creating an updated archive. No API keys are required for the connected ChatGPT plan.

## 4. Migrate your journal and ChatGPT connection

Finish any active photo estimate and stop the laptop server with Ctrl+C. From a local terminal in the project:

```sh
node scripts/prepare-migration.mjs --source-stopped
```

This creates a protected `migration/TIMESTAMP/` snapshot containing SQLite plus its encryption key. It copies accounts, journals, habit records, and encrypted ChatGPT credentials, assigns a new VM host ID, and removes browser sessions so you sign in again on the phone. It does not modify or delete your original database. The snapshot is secret: do not commit it, send it in chat, or place it in public file storage.

Transfer the printed snapshot directory over SSH into an empty data directory on the new server:

```sh
ssh root@DROPLET_IP 'install -d -m 700 /opt/bite-by-bite/data'
scp -r migration/TIMESTAMP/. root@DROPLET_IP:/opt/bite-by-bite/data/
```

Use an empty target for the first migration; do not overwrite an existing server journal. Keep the laptop server stopped after the transfer. The VM must be the only runtime renewing this copied ChatGPT session. OpenAI’s [self-hosted VM instructions](https://developers.openai.com/siwc/token-sharing-open-source/self-hosted-vms) describe the credential-transfer method and its current attribution/revocation limitations. Retain the VM’s new host ID on later updates. This deployment is for your own personal use; a commercial or multi-user service is outside this setup.

## 5. Start and verify

On the fresh Droplet:

```sh
cd /opt/bite-by-bite
bash deploy/install.sh
```

The installer installs Docker and Compose from Ubuntu packages, sets private data permissions, starts the app and Caddy, closes registration, and schedules daily SQLite backups at 03:00 UTC. Containers restart automatically after reboot. The app binds only to 127.0.0.1:3000. The compose file uses Linux host networking and is intended for the Ubuntu Droplet, not Docker Desktop on macOS.

Open `https://YOUR_HOSTNAME` and verify:

1. The browser trusts HTTPS.
2. Your existing username/password loads your journal.
3. Creating new accounts is disabled.
4. Settings shows the expected ChatGPT connection.
5. One photo produces an estimate and saves after review.
6. Water, supplements, and edits remain after signing out and back in.

Automated local tests do not replace these live checks. If certificate provisioning fails, verify DNS, firewall rules, and port availability. Inspect container state and logs with:

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml ps
docker compose --env-file deploy/.env -f deploy/compose.yaml logs --tail=80
```

Do not share logs containing authorization URLs or credentials.

## 6. Install on your phone

On iPhone, open the HTTPS link in Safari → Share → Add to Home Screen. On Android, open it in Chrome → menu → Install app/Add to Home screen. Sign in to the same journal account. Your laptop can now stay off. Internet and a running Droplet are required for account access and photo estimates. Reminders still run only while the app is active; this deployment does not add background push.

## Backups and updates

Verify the scheduled backup with `systemctl list-timers bite-backup.timer` and `journalctl -u bite-backup.service`. Run one immediately:

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml exec -T app node scripts/backup.mjs /app/data /backups
```

Each backup includes the SQLite snapshot and encryption key. Backups on the same Droplet do not protect against losing/deleting the Droplet. Download protected backups over SSH or configure separately approved off-server backups. No paid DigitalOcean backup service is enabled by these files. Retention cleanup is manual.

For source updates, preserve `data/`, `backups/`, `deploy/.env`, and Caddy volumes, upload only the changed source, and run the compose `up -d --build` command again. Never use `down --volumes` for normal updates. Keep the OS and container images updated.

If ChatGPT requires fresh consent later, complete it locally through an SSH tunnel to the VM instead of creating a second active laptop session. Stop the local app and run `ssh -L 3000:127.0.0.1:3000 root@DROPLET_IP`, open `http://localhost:3000`, sign in with your journal account, and use Continue with ChatGPT. Loopback cookies are deliberately usable over HTTP for this SSH-encrypted local path; public-domain cookies remain Secure. Close the tunnel after authorization; the VM continues refreshing its connection.

Sources: [DigitalOcean pricing](https://www.digitalocean.com/pricing/droplets), [Droplet creation](https://docs.digitalocean.com/products/droplets/how-to/create/), [Caddy HTTPS](https://caddyserver.com/docs/automatic-https), [OpenAI VM setup](https://developers.openai.com/siwc/token-sharing-open-source/self-hosted-vms).
