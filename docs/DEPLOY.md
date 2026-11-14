# Deploying Gremlo

Three pieces: the API (a free VM, or Fly.io), the web app (Vercel), the Mac app (`install.sh` or the release dmg). The vault is `vault.gremlo.testnet` on NEAR testnet.
Secrets live only in each host's secret store. Never commit them, never put them in the image.
Nothing here has been deployed yet. The configs are ready: `deploy/vm/` (systemd, Caddy, health check), `apps/web/vercel.json`, `apps/server/fly.toml`.

## 1. API on a free VM (Oracle Cloud or Google Cloud)

One small Linux VM runs the API under systemd, behind Caddy for HTTPS, with its data on a persistent disk.
Free options: Oracle Cloud Always Free (an Ampere A1 VM; Mumbai is `ap-mumbai-1`) or Google Cloud's free e2-micro
(1 GB RAM, US regions only). Ubuntu 22.04 or 24.04. The files are in `deploy/vm/`.

**The VM, its disk, its address**

- Give the VM a static public IP (Oracle: a reserved public IP; Google: a static external IP).
- Attach a second disk for the data (Oracle: a block volume; Google: a persistent disk), so the data outlives the VM.
- Point a DNS A record, e.g. `api.example.com`, at the IP. Caddy needs a real name to get a certificate.
- Open TCP 80 and 443. Oracle needs both the VCN security list and the VM's own firewall
  (`sudo iptables -I INPUT 6 -p tcp -m multiport --dports 80,443 -m state --state NEW -j ACCEPT && sudo netfilter-persistent save`).
  Google: tick Allow HTTP and HTTPS on the VM, or add a firewall rule for tcp:80,443.

```bash
# the data disk, mounted at /data (mkfs only the first time: it erases the disk)
lsblk                                            # find it, e.g. /dev/sdb
sudo mkfs.ext4 -L gremlo-data /dev/sdb
sudo mkdir -p /data && echo 'LABEL=gremlo-data /data ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab && sudo mount /data

# Node 22, git, and Caddy (Caddy's apt repo: caddyserver.com/docs/install#debian-ubuntu-raspbian)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs git
sudo apt-get install -y caddy                    # after adding Caddy's repo as its docs say

# the code, read-only to the service; the data, writable only by it
sudo useradd --system --no-create-home --shell /usr/sbin/nologin gremlo
sudo git clone https://github.com/DiveshK007/GREMLO.git /opt/gremlo
(cd /opt/gremlo/apps/server && sudo npm ci)       # tsx is a dev dependency and the server runs on it
sudo install -d -o gremlo -g gremlo -m 700 /data/gremlo
```

**Secrets.** They go in one root-only file that systemd reads before it drops to the `gremlo` user, so the service
can't read the file itself and nothing lands in the repo or the shell history:

```bash
sudo install -d -m 700 /etc/gremlo
sudo install -m 600 /dev/null /etc/gremlo/api.env
sudoedit /etc/gremlo/api.env
```

One `NAME=value` per line, no quotes: `NEAR_NETWORK`, `NEAR_CONTRACT_ID`, `NEAR_RPC_URL`, `NEAR_OPERATOR_ACCOUNT_ID`,
`NEAR_OPERATOR_PRIVATE_KEY`, `NEAR_AI_BASE_URL`, `NEAR_AI_API_KEY`, `NEAR_AI_MODEL_SMART`, `NEAR_AI_MODEL_CHEAP`,
`COMPUTE_FEE_SMART_YOCTO`, `COMPUTE_FEE_CHEAP_YOCTO`, `WORLD_APP_ID`, `RP_ID`, `RP_SIGNING_KEY`,
`WEB_ORIGIN=https://<your-vercel-domain>`, and the optional ones from HANDOFF (`PURSE_PARENT` only once the purse
factory is deployed). The unit itself sets the rest: `HOST=127.0.0.1`, `PORT=8787`, `REQUIRE_SIGNED=1`,
`TRUST_PROXY=1`, `HOLDBACK_HOURS=24`, and the store, logs and gallery under `/data/gremlo`.

**Services**

```bash
cd /opt/gremlo/deploy/vm
sudo cp gremlo-api.service gremlo-health.service gremlo-health.timer /etc/systemd/system/
sudo install -m 755 gremlo-health /usr/local/bin/gremlo-health
sudo cp Caddyfile /etc/caddy/Caddyfile && sudoedit /etc/caddy/Caddyfile     # replace api.example.com with your name
sudo systemctl daemon-reload
sudo systemctl enable --now gremlo-api gremlo-health.timer
sudo systemctl reload caddy
curl https://api.example.com/health               # 200 with "ok": true
journalctl -u gremlo-api -f                       # the worker logs here
```

The API listens only on loopback. Caddy faces the internet, renews the certificate, and overwrites the client-IP
headers so nobody can fake an IP past the rate limits and fraud rules.

**Health.** `/health` answers 503 with plain reasons when the settlement worker stalls, the operator account is
under 0.5 NEAR, or views expired unpaid.
- On the VM, `gremlo-health.timer` checks it every 5 minutes and logs failures (`journalctl -u gremlo-health`).
  Put `ALERT_URL=` (an ntfy.sh topic or a chat webhook that takes a plain POST) in `/etc/gremlo/health.env` to be told.
- The VM can't report its own death, so also add an outside monitor (UptimeRobot or Better Stack, free) on
  `https://api.example.com/health`, alerting on anything but 200.

**Updating:** `cd /opt/gremlo && sudo git pull --ff-only && (cd apps/server && sudo npm ci) && sudo systemctl restart gremlo-api`

**Backups:** schedule snapshots of the data disk (Oracle: a volume backup policy; Google: a snapshot schedule).
`/data/gremlo` holds the whole store and the signed logs.

Limits: one instance only (the store is a single file). The operator key sits in `/etc/gremlo/api.env`, readable by
root on that VM; move it to a KMS before mainnet.

## 1b. API on Fly.io (alternative)

The Dockerfile builds from the repo root because the server imports `packages/brain`.

```bash
fly auth login
(cd apps/server && fly launch --no-deploy --copy-config --name <your-app-name>)  # keeps fly.toml; set `app` to your name
fly volumes create gremlo_data --size 1 --region bom -a <your-app-name>             # the JSON store (STORE_PATH=/data/data.json)
fly secrets set -a <your-app-name> \
  NEAR_NETWORK=testnet NEAR_CONTRACT_ID=vault.gremlo.testnet NEAR_RPC_URL=... \
  NEAR_OPERATOR_ACCOUNT_ID=operator.gremlo.testnet NEAR_OPERATOR_PRIVATE_KEY=... \
  NEAR_AI_BASE_URL=... NEAR_AI_API_KEY=... NEAR_AI_MODEL_SMART=... NEAR_AI_MODEL_CHEAP=... \
  COMPUTE_FEE_SMART_YOCTO=... COMPUTE_FEE_CHEAP_YOCTO=... \
  WORLD_APP_ID=... RP_ID=... RP_SIGNING_KEY=... \
  WEB_ORIGIN=https://<your-vercel-domain>
  # optional: PURSE_PARENT (only once the purse factory is deployed), GALLERY_REVIEW_TOKEN,
  # RESEND_API_KEY + MAIL_FROM (brand emails), ARKIV + ARKIV_KEY + ARKIV_ACCESS_KEY
fly deploy . -c apps/server/fly.toml --dockerfile apps/server/Dockerfile                # from the repo root
curl https://<your-app-name>.fly.dev/health                                             # 200 with "ok": true
```

The Fly health check polls `/health`, which answers 503 with plain reasons when the settlement worker stalls,
the operator account is under 0.5 NEAR, or views expired unpaid. Point an uptime monitor at the same URL.

Production settings baked into the image: `HOST=0.0.0.0`, `REQUIRE_SIGNED=1` (every view, think and click must be signed by a paired Mac),
`TRUST_PROXY=1` (rate limits use Fly's client IP), `STORE_PATH=/data/data.json`. The server refuses to listen publicly without `REQUIRE_SIGNED=1`.

Copy the existing store once if you want history: `fly ssh sftp shell` then `put data.json /data/data.json` (stop the old server first).

Limits that matter in production: one machine only (the store is a single file; move to Postgres before scaling out, see PLAN_V2 A2),
and the operator key is a Fly secret (encrypted at rest). Move it to a KMS or multisig before mainnet (PLAN_V2 E4).

## 2. Web on Vercel

`apps/web/vercel.json` sets the framework and `npm ci`. Node 22 comes from `engines` in `package.json`.

```bash
cd apps/web
vercel link            # root directory: apps/web
vercel env add NEXT_PUBLIC_SERVER_URL production        # https://api.example.com (or the fly.dev URL)
vercel env add NEXT_PUBLIC_WEB_URL production           # https://<your-vercel-domain>
vercel env add NEXT_PUBLIC_NEAR_NETWORK production      # testnet
vercel env add NEXT_PUBLIC_NEAR_CONTRACT_ID production  # vault.gremlo.testnet
vercel env add NEXT_PUBLIC_NEAR_RPC_URL production
vercel env add NEXT_PUBLIC_WORLD_APP_ID production
vercel env add NEXT_PUBLIC_WORLD_RP_ID production
vercel env add NEXT_PUBLIC_WORLD_ENV production         # staging until World production is configured
vercel env add NEXT_PUBLIC_WORLD_PRESET production
vercel --prod
```

Then set `WEB_ORIGIN` on the API to the Vercel URL (CORS): in `/etc/gremlo/api.env` and `sudo systemctl restart gremlo-api`, or as a Fly secret.
After deploying, `E2E_BASE_URL=https://<your-vercel-domain> npm run e2e` runs the page checks against it.

## 3. Mac app

Point it at production with `GREMLO_SERVER=https://api.example.com GREMLO_WEB=https://<your-vercel-domain>`
(for an app opened from Finder: `launchctl setenv GREMLO_SERVER ...`, then reopen it).
Each user then pairs their Mac once: Gremlo menu → Settings → Pair this Mac with my pet (signs with the pet owner's wallet).
Signed, notarised .dmg + Sparkle auto-update need an Apple Developer account; see PLAN_V2 phase G.

## Arkiv (optional)

Get an access key at hub.arkiv.network/access-keys and testnet tGLM for the `ARKIV_KEY` account at hub.arkiv.network/faucet.
With both set, each saved campaign publishes a `gremlo.campaign` card and each settlement a `gremlo.receipt`, all expiring with the campaign.
Without them Arkiv is simply off; nothing else changes.

## Brand emails (optional)

Brands can leave an email when they fund a campaign. With `RESEND_API_KEY` and `MAIL_FROM` (a sender on a domain verified in Resend)
set, the worker emails each level of budget alert once (50, 80, 100% spent) and a weekly report (views, verified humans, clicks,
spend, best hook). Addresses stay in the server store; they are never served back or published. Without the keys mail is off.

## The pet's purse (optional, not deployed)

A pet with a purse pays for each thought from its own account, signed on the Mac with a key that can only call
`pay_inference`. Deploy the factory and create a purse with the steps in `contracts-accounts/README.md`, then set
`PURSE_PARENT` on the API. Without it every pet pays from its vault budget, as now.

## Holdback and fraud rules

Views wait `HOLDBACK_HOURS` (24 in the Docker image, 0 locally) before they can be paid. Then fixed rules void what
looks like a farm (more than 3 pets from one network in an hour) or a script (a pet seen in more than 20 hours of a
day). Voided views are never charged; brands see the count and reason. When a campaign ends, held views are reviewed
at once, because the contract pays for only one more hour.

## 4. Checks after deploying

- `GET /health` is ok; `GET /stats` returns numbers from the chain.
- A new campaign funded on the web app shows on a paired Mac within 10 s.
- An unsigned `POST /impressions` from curl gets 401.
- The worker logs `worker: settled campaign N` within 10 minutes of queued views.

## Mac app: signed, notarized dmg

Until there's an Apple Developer account: `install.sh` builds on the user's Mac (no Gatekeeper warning), and pushing a
`v*` tag makes `.github/workflows/release.yml` attach an ad hoc signed dmg to the release (README, Install, has the
first-launch steps). With an account:


`scripts/release-mac.sh` builds a universal `Gremlo.app` (pets and hook script inside), wraps it in a dmg, and with your Apple Developer account signs, notarizes and staples it. You need:

1. An Apple Developer Program membership and a "Developer ID Application" certificate in your keychain. `security find-identity -v -p codesigning` shows its name.
2. A notarytool profile, made once: `xcrun notarytool store-credentials gremlo --apple-id you@example.com --team-id TEAMID --password <app-specific password>`.
3. `SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=gremlo VERSION=0.2.0 ./scripts/release-mac.sh`

Output: `apps/mac/dist/Gremlo-<version>.dmg`. Without `SIGN_ID` the script signs ad hoc, so the app runs only on the Mac that built it. CI runs it unsigned to prove the bundle builds. There is no auto-update yet; ship a new dmg per version.
