# Chatly — Production Hosting Guide

This guide walks you through deploying the complete Chatly stack to production
using free and low-cost managed services. The recommended stack is:

| Service | What it handles | Free tier |
|---|---|---|
| **Railway** | Node.js backend hosting | 500 hrs/month |
| **Supabase** | PostgreSQL database | 500 MB included |
| **Upstash** | Redis for offline message queuing | 10,000 req/day |
| **Cloudflare** | DNS + SSL + CDN proxy | Free |

---

## Step 1 — Set Up the PostgreSQL Database (Supabase)

1. Go to [supabase.com](https://supabase.com) and create a free account.
2. Click **New Project**, choose a name (e.g., `chatly-prod`) and a strong database password.
3. After the project provisions (~2 minutes), go to **Project Settings → Database**.
4. Copy the **Connection string** under the URI tab. It looks like:
   ```
   postgresql://postgres:[YOUR-PASSWORD]@db.[PROJECT-ID].supabase.co:5432/postgres
   ```
5. Save this — it becomes your `DATABASE_URL` environment variable.

> **Note**: Chatly's server automatically creates all required tables on first boot via
> `initializeDatabase()`. You do not need to run any migrations manually.

---

## Step 2 — Set Up Redis for Offline Queuing (Upstash)

1. Go to [upstash.com](https://upstash.com) and create a free account.
2. Click **Create Database**, choose a region closest to your Railway deployment.
3. After creation, open the database and copy the **Redis URL** from the Connect tab:
   ```
   rediss://default:[PASSWORD]@[ENDPOINT]:6379
   ```
4. Save this — it becomes your `REDIS_URL` environment variable.

> **Note**: If `REDIS_URL` is not set, the server automatically uses an in-memory
> Map fallback. This is fine for small-scale or single-instance deployments, but
> offline message queuing will not survive server restarts.

---

## Step 3 — Deploy the Backend on Railway

1. Go to [railway.app](https://railway.app) and create a free account.
2. Click **New Project → Deploy from GitHub Repo**.
3. Connect your GitHub account and select the `chatlypro` repository.
4. Railway will auto-detect Node.js. Set the **Root Directory** to `packages/chatly-server`.
5. Go to the **Variables** tab and add the following:

   | Key | Value |
   |---|---|
   | `DATABASE_URL` | Your Supabase connection string |
   | `REDIS_URL` | Your Upstash Redis URL |
   | `JWT_SECRET` | A strong random 64-character string (use `openssl rand -hex 32`) |
   | `NODE_ENV` | `production` |
   | `ALLOWED_ORIGINS` | `https://your-flutter-web-app-domain.com` |
   | `PORT` | `5000` |

6. Go to **Settings → Networking** and enable a **Public Domain**. Note the generated URL, e.g.:
   ```
   https://chatly-production.up.railway.app
   ```

7. Railway will build and deploy automatically on every push to `main`.

---

## Step 4 — Deploy the ML Service on Railway (Optional)

1. In the same Railway project, click **+ New Service → GitHub Repo**.
2. Set the **Root Directory** to `packages/chatly-ml`.
3. Railway detects Python automatically. No additional variables needed.
4. The ML service runs on port `8000` internally. The Fastify server talks to it
   via the internal Railway network using the service hostname.

> **Note**: If the ML service is unavailable, the backend's toxicity classification
> falls back to a keyword regex filter automatically. The ML service is optional.

---

## Step 5 — Custom Domain + SSL (Cloudflare)

1. Register a domain (e.g., `chatly.app`) at your preferred registrar.
2. Create a free [Cloudflare](https://cloudflare.com) account and add your domain.
3. In Cloudflare DNS, add a **CNAME** record:
   - Name: `api`
   - Target: your Railway domain (e.g., `chatly-production.up.railway.app`)
   - Proxy: **Enabled** (orange cloud)
4. Set Cloudflare SSL mode to **Full (strict)**.
5. Your backend is now accessible at `https://api.chatly.app` with automatic HTTPS.

---

## Step 6 — Update the Flutter App for Production

Build the Flutter app with the production server URL:

```bash
# Android APK
flutter build apk --release \
  --dart-define=BASE_URL=https://api.chatly.app/api \
  --dart-define=WS_URL=wss://api.chatly.app

# Windows EXE
flutter build windows --release \
  --dart-define=BASE_URL=https://api.chatly.app/api \
  --dart-define=WS_URL=wss://api.chatly.app

# Web
flutter build web --release \
  --dart-define=BASE_URL=https://api.chatly.app/api \
  --dart-define=WS_URL=wss://api.chatly.app
```

The `--dart-define` flags are read by `lib/core/config/app_config.dart` at compile
time and baked into the binary — no runtime config files are needed.

---

## Monitoring & Logs

- **Railway**: Click your service → **Logs** tab for real-time stdout/stderr.
- **Supabase**: Use the SQL Editor to inspect the `users` table and confirm registrations.
- **Health Check**: Visit `https://api.chatly.app/` to confirm the server is running.
  The JSON response includes the current version, environment, and uptime timestamp.

---

## Security Checklist Before Going Live

- [ ] `JWT_SECRET` is set to a random 64-character string
- [ ] `NODE_ENV=production` is set
- [ ] `ALLOWED_ORIGINS` is restricted to your actual frontend domain
- [ ] SSL/HTTPS is enforced (Cloudflare Full Strict mode)
- [ ] Database password is strong and not reused anywhere
- [ ] Repository has no `.env` files committed (check with `git log -- .env`)
