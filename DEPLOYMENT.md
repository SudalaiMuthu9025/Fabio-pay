# Fabio — Deployment & Public Launch Guide

> **Complete step-by-step instructions** to take Fabio from local development  
> to a production-ready, publicly hosted FinTech application.

---

## 1. Database Hosting (Supabase — Managed PostgreSQL)

### 1.1 Create the Database

1. Go to [supabase.com](https://supabase.com) → **New Project**
2. Set a **strong database password** (save it — you'll need it)
3. Choose the region closest to your users (e.g. `ap-south-1` for India)
4. Wait for provisioning (~2 minutes)

### 1.2 Get the Connection String

1. **Project Settings → Database → Connection string → URI**
2. Format:
   ```
   postgresql+asyncpg://<user>:<password>@<host>:5432/postgres
   ```
3. Copy this — it becomes your `DATABASE_URL` env var

### 1.3 Security Hardening

- Enable **Row Level Security (RLS)** on all tables
- Under **Auth → Settings**, disable email confirmations for dev, enable for prod
- Use Supabase **connection pooling** (port `6543`) for production workloads

---

## 2. Backend Hosting (Render)

### 2.1 Deploy the Docker Container

1. Push your code to **GitHub** (ensure `Dockerfile` is at `backend/` root)
2. Go to [render.com](https://render.com) → **New → Web Service**
3. Connect your GitHub repo → set **Root Directory** to `backend/`
4. Render auto-detects the Dockerfile

### 2.2 Environment Variables

Set these in Render's **Environment** tab:

| Variable | Value |
|---|---|
| `DATABASE_URL` | `postgresql+asyncpg://...` (from Supabase) |
| `SECRET_KEY` | Generate: `openssl rand -hex 32` |
| `ALGORITHM` | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `30` |
| `DEBUG` | `false` |
| `PANIC_TIMER_SECONDS` | `15` |

### 2.3 WebSocket Support

- Render natively supports WebSockets on all plans
- Your Flutter app connects to: `wss://your-app.onrender.com/ws/liveness`
- ⚠️ **Free-tier services sleep after 15 min of inactivity** — use a paid plan for production

### 2.4 Alternative: Railway

1. [railway.app](https://railway.app) → **New Project → Deploy from GitHub**
2. Set Root Directory to `backend/`
3. Railway auto-detects Dockerfiles
4. Add the same env vars in the **Variables** tab
5. Railway supports WebSockets and custom domains

---

## 3. Domain & SSL (Cloudflare)

### 3.1 DNS Setup

1. Register a domain (e.g. `fabiopay.com`) via any registrar
2. Go to [cloudflare.com](https://cloudflare.com) → **Add Site**
3. Point nameservers to Cloudflare (registrar settings)
4. Add DNS records:

| Type | Name | Content |
|---|---|---|
| `CNAME` | `api` | `your-app.onrender.com` |
| `CNAME` | `@` | `your-frontend.vercel.app` (if web) |

### 3.2 SSL Configuration

1. **SSL/TLS → Overview** → Set to **Full (Strict)**
2. Enable **Always Use HTTPS**
3. Enable **HSTS** (Header Strict Transport Security)

> ⚠️ **Strict SSL is mandatory** — mobile browsers require HTTPS for camera permissions, and WebSockets must use `wss://` in production.

---

## 4. Mobile Publishing

### 4.1 Android (.aab — Google Play Store)

#### Build the Release

```bash
cd frontend
flutter clean
flutter pub get
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

#### Play Store Submission Checklist

- [ ] Create a **Google Play Developer account** ($25 one-time)
- [ ] Create app listing with screenshots (phone + 7" tablet)
- [ ] Upload the `.aab` in **Production → Create Release**
- [ ] Complete the **Data Safety** form:
  - ✅ Collects **biometric data** (facial geometry for liveness)
  - ✅ Collects **financial data** (bank accounts, transactions)
  - ✅ Data encrypted in transit (HTTPS/WSS)
  - ✅ Data processed on-server, **not stored permanently**
- [ ] Add a **Privacy Policy URL** (required — see §4.3)
- [ ] Set content rating (IARC questionnaire)
- [ ] Submit for review (~3-7 days)

### 4.2 iOS (.ipa — Apple App Store)

#### Build the Release

```bash
flutter build ipa --release
```

Output: `build/ios/ipa/Fabio.ipa`

#### App Store Submission Checklist

- [ ] **Apple Developer Program** membership ($99/year)
- [ ] Configure Xcode signing (Team, Bundle ID, Provisioning Profile)
- [ ] Upload via **Transporter** app or `xcrun altool`
- [ ] In **App Store Connect**:
  - Add app description, screenshots, keywords
  - Set **Privacy Nutrition Labels**:
    - 📸 Camera: Used for liveness verification
    - 🆔 Face data: Used for anti-spoofing, not stored
    - 💰 Financial info: Bank accounts and transactions
- [ ] **NSCameraUsageDescription** in `Info.plist`:
  ```
  Fabio requires camera access for Active Liveness verification during high-value transactions.
  ```
- [ ] Submit for App Review (~1-3 days)

### 4.3 Privacy Policy (Required by Both Stores)

Your privacy policy **must** disclose:

1. **What biometric data is collected** — facial landmark geometry (468 3D points)
2. **Why** — real-time anti-spoofing liveness verification
3. **How it's processed** — on-server via MediaPipe, not stored after verification
4. **No facial recognition** — Fabio does NOT identify individuals, only verifies liveness
5. **Financial data handling** — encrypted at rest and in transit
6. **Data retention** — challenge results logged for audit; raw frames are discarded
7. **GDPR/CCPA compliance** — right to deletion, right to data export

> Host the privacy policy at `https://fabiopay.com/privacy` and link it in both store listings.

---

## 5. Production Checklist

| # | Item | Status |
|---|---|---|
| 1 | PostgreSQL hosted & connection string set | ☐ |
| 2 | `SECRET_KEY` rotated from dev default | ☐ |
| 3 | `DEBUG=false` in production | ☐ |
| 4 | HTTPS/WSS enforced via Cloudflare | ☐ |
| 5 | CORS origins restricted to your domain | ☐ |
| 6 | Rate limiting enabled on auth endpoints | ☐ |
| 7 | Privacy policy published & linked | ☐ |
| 8 | Android `.aab` built & uploaded | ☐ |
| 9 | iOS `.ipa` built & uploaded | ☐ |
| 10 | End-to-end liveness flow tested on real device | ☐ |
