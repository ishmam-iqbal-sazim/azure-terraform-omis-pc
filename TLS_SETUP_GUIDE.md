# TLS/HTTPS Setup Guide

## What is TLS?

**TLS (Transport Layer Security)** is a cryptographic protocol that provides secure communication over a network. When you visit a website with `https://` instead of `http://`, TLS is encrypting your connection.

**Why do we need it?**
- **Encryption**: Prevents eavesdropping on data in transit (passwords, API tokens, user data)
- **Authentication**: Verifies you're connecting to the real server, not an imposter
- **Data Integrity**: Ensures data isn't tampered with during transmission
- **Trust**: Modern browsers show warnings for non-HTTPS sites
- **SEO & Features**: Some browser features (like geolocation, camera access) require HTTPS

**See [INFRASTRUCTURE_GUIDE.md Part 17](#) for a deep dive into how TLS works.**

---

## Current Setup (Without Domain)

### What's Already Configured

The infrastructure includes **Caddy**, a reverse proxy that:
- Automatically handles HTTPS when you add a domain
- Provides automatic certificate provisioning via Let's Encrypt
- Handles HTTP→HTTPS redirects
- Manages certificate renewals automatically

**Current Access Pattern:**
```
User Browser → http://<VM_PUBLIC_IP>:80 → Caddy → Internal Services
                                            ↓
                                         frontend:3000
                                         backend:5000
                                         backend:5001 (WebSocket)
```

**What this means:**
- ✅ Your services are running and accessible
- ✅ Caddy is proxying requests correctly
- ⚠️ Traffic is **NOT encrypted** (HTTP only)
- ⚠️ Browser will show "Not Secure" warning
- ⚠️ Data is transmitted in plain text

**This is acceptable for:**
- Initial testing and development
- Internal/private networks
- Before you have a domain name

**This is NOT acceptable for:**
- Production with real users
- Handling sensitive data (passwords, personal info)
- Compliance requirements (PCI-DSS, HIPAA, etc.)

---

## Enabling HTTPS (When You Get a Domain)

### Prerequisites

1. **A domain name** (e.g., `omis-pc.example.com`)
   - Purchase from registrar (Namecheap, GoDaddy, CloudFlare, etc.)
   - You control the DNS settings

2. **VM with public IP** (already have this)
   - Current IP: `20.245.121.120` (from terraform output)

3. **Ports 80 and 443 open** (already configured in NSG)

### Step 1: Configure DNS

Point your domain to the VM's public IP address:

```
┌─────────────────────────────────────────────────────────────┐
│                   DNS CONFIGURATION                          │
│                                                              │
│   Your Domain Registrar (e.g., Namecheap)                   │
│   ────────────────────────────────────                       │
│                                                              │
│   Type: A Record                                             │
│   Name: @ (root) or "app" (subdomain)                       │
│   Value: 20.245.121.120 ←─── Your VM's Public IP            │
│   TTL: 3600 seconds (1 hour)                                 │
│                                                              │
│   Example configurations:                                    │
│   ┌─────────────────────────────────────────────┐           │
│   │ omis-pc.example.com → 20.245.121.120        │           │
│   │ (A record for root domain)                  │           │
│   └─────────────────────────────────────────────┘           │
│   ┌─────────────────────────────────────────────┐           │
│   │ app.example.com → 20.245.121.120            │           │
│   │ (A record for subdomain)                    │           │
│   └─────────────────────────────────────────────┘           │
│                                                              │
│   After saving, DNS propagates globally:                    │
│   ─────────────────────────────────────                     │
│                                                              │
│   You (5 min)  →  ✅ Can see change                          │
│   Your ISP (1 hr)  →  ✅ Cache updated                       │
│   Global (24-48 hr)  →  ✅ Worldwide propagation            │
└─────────────────────────────────────────────────────────────┘
```

**Wait for DNS propagation** (can take 5 minutes to 48 hours):
```bash
# Check DNS propagation
dig omis-pc.example.com
nslookup omis-pc.example.com

# Should return:
# omis-pc.example.com.  3600  IN  A  20.245.121.120
```

**DNS Propagation Visualization:**
```
┌─────────────────────────────────────────────────────────────┐
│              DNS PROPAGATION TIMELINE                        │
│                                                              │
│   T+0min:  You update DNS record                             │
│            │                                                 │
│   T+5min:  ├──► Your location can resolve ✅                 │
│            │                                                 │
│   T+1hr:   ├──► Your ISP's DNS cache updates ✅              │
│            │                                                 │
│   T+6hr:   ├──► Most of your country resolves ✅             │
│            │                                                 │
│   T+24hr:  ├──► 95% of world can resolve ✅                  │
│            │                                                 │
│   T+48hr:  └──► 99.9% of world can resolve ✅                │
│                                                              │
│   Factors affecting speed:                                   │
│   • TTL value (lower = faster propagation)                   │
│   • DNS provider (CloudFlare faster than others)             │
│   • Geographic location                                      │
└─────────────────────────────────────────────────────────────┘
```

### Step 2: Update Environment Configuration

SSH into your VM:
```bash
ssh azureuser@20.245.121.120
cd /opt/omis-pc
```

Edit the `.env` file to add your domain:
```bash
# Add or update this line
DOMAIN=omis-pc.example.com

# Update URLs to use HTTPS
WEB_CLIENT_BASE_URL=https://omis-pc.example.com
NEXT_PUBLIC_API_BASE_URL=https://omis-pc.example.com/api/v1/
NEXT_PUBLIC_WS_BASE_URL=wss://omis-pc.example.com
```

**Important Environment Variable Updates:**

```bash
# Before (HTTP only)
WEB_CLIENT_BASE_URL=http://20.245.121.120:3000
NEXT_PUBLIC_API_BASE_URL=http://20.245.121.120:5000/api/v1/
NEXT_PUBLIC_WS_BASE_URL=ws://20.245.121.120:5001

# After (HTTPS with domain)
WEB_CLIENT_BASE_URL=https://omis-pc.example.com
NEXT_PUBLIC_API_BASE_URL=https://omis-pc.example.com/api/v1/
NEXT_PUBLIC_WS_BASE_URL=wss://omis-pc.example.com
```

### Step 3: Restart Services

```bash
cd /opt/omis-pc
docker compose down
docker compose up -d
```

### Step 4: Verify HTTPS is Working

**What Caddy Does Automatically:**

```
┌─────────────────────────────────────────────────────────────┐
│         CADDY AUTOMATIC HTTPS SETUP PROCESS                  │
│                                                              │
│   1. Startup Detection                                       │
│   ┌──────────────────────────────────────┐                  │
│   │ Caddy reads: DOMAIN=omis-pc.com      │                  │
│   │ "I need a certificate for this!"     │                  │
│   └──────────────┬───────────────────────┘                  │
│                  │                                           │
│   2. Contact Let's Encrypt                                   │
│   ┌──────────────▼───────────────────────┐                  │
│   │ Caddy → Let's Encrypt Authority      │                  │
│   │ "Please give me a cert for omis-pc"  │                  │
│   └──────────────┬───────────────────────┘                  │
│                  │                                           │
│   3. Domain Ownership Challenge                              │
│   ┌──────────────▼───────────────────────┐                  │
│   │ Let's Encrypt → Caddy                │                  │
│   │ "Prove you own it: serve this file:" │                  │
│   │ http://omis-pc.com/.well-known/      │                  │
│   │        acme-challenge/abc123"        │                  │
│   └──────────────┬───────────────────────┘                  │
│                  │                                           │
│   4. Caddy Serves Challenge                                  │
│   ┌──────────────▼───────────────────────┐                  │
│   │ Let's Encrypt checks:                │                  │
│   │ GET http://omis-pc.com/.well-known/  │                  │
│   │          acme-challenge/abc123       │                  │
│   │ Response: ✅ Correct!                 │                  │
│   └──────────────┬───────────────────────┘                  │
│                  │                                           │
│   5. Certificate Issued                                      │
│   ┌──────────────▼───────────────────────┐                  │
│   │ Let's Encrypt → Caddy                │                  │
│   │ "Here's your certificate!"           │                  │
│   │ [Certificate + Private Key]          │                  │
│   └──────────────┬───────────────────────┘                  │
│                  │                                           │
│   6. HTTPS Enabled                                           │
│   ┌──────────────▼───────────────────────┐                  │
│   │ Caddy configures:                    │                  │
│   │ • Port 443 with TLS                  │                  │
│   │ • HTTP→HTTPS redirect on port 80     │                  │
│   │ • Certificate stored in /data/       │                  │
│   │ • Auto-renewal scheduled (day 60)    │                  │
│   └──────────────────────────────────────┘                  │
│                                                              │
│   Total time: 30-60 seconds ⚡                               │
└─────────────────────────────────────────────────────────────┘
```

**The process broken down:**
1. ✅ Detects the `DOMAIN` environment variable
2. ✅ Contacts Let's Encrypt to request a certificate
3. ✅ Proves domain ownership via HTTP-01 challenge
4. ✅ Downloads the certificate
5. ✅ Configures HTTPS on port 443
6. ✅ Sets up automatic renewals (certificates expire every 90 days)

**Check Caddy logs:**
```bash
docker compose logs caddy
```

You should see:
```
successfully obtained certificate
certificate obtained successfully
```

**Test in browser:**
```
https://omis-pc.example.com
```

**Expected results:**
- ✅ Green padlock in browser
- ✅ Certificate shows "Let's Encrypt Authority"
- ✅ No security warnings
- ✅ HTTP traffic redirects to HTTPS

### Step 5: Test WebSocket (WSS)

WebSockets also use TLS when accessed via `wss://`:

```bash
# Test WebSocket connection
wscat -c wss://omis-pc.example.com

# Should connect successfully with TLS encryption
```

---

## How Caddy's Automatic HTTPS Works

### The Caddyfile Configuration

Located at `/opt/omis-pc/Caddyfile` (deployed via cloud-init):

```caddyfile
{
  admin off
  auto_https disable_redirects
}

# HTTP block (port 80) - used when NO domain
:80 {
  handle /api/v1/* {
    reverse_proxy backend:5000
  }
  handle /api/* {
    reverse_proxy backend:5000
  }
  handle /* {
    reverse_proxy frontend:3000
  }
}

# HTTPS block (port 443) - used when DOMAIN is set
{$DOMAIN:} {
  handle /api/v1/* {
    reverse_proxy backend:5000
  }
  handle /api/* {
    reverse_proxy backend:5000
  }
  handle /* {
    reverse_proxy frontend:3000
  }
  
  # Security headers
  header {
    X-Content-Type-Options nosniff
    X-Frame-Options DENY
    Referrer-Policy strict-origin-when-cross-origin
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
  }
}
```

**Key Points:**
- `{$DOMAIN:}` block activates when `DOMAIN` env var is set
- Caddy automatically provisions TLS for any domain in the Caddyfile
- No manual certificate management needed
- `auto_https` directive handles HTTP→HTTPS redirects
- HSTS header enforces HTTPS for future visits

---

## Troubleshooting

### Issue: "Can't obtain certificate"

**Symptoms:**
```
caddy: error obtaining certificate
acme: challenge failed
```

**Causes & Solutions:**

1. **DNS not propagated**
   ```bash
   # Check DNS is pointing to your VM
   dig omis-pc.example.com
   # Should show: 20.245.121.120
   ```

2. **Firewall blocking ports 80/443**
   ```bash
   # Verify NSG rules allow traffic
   # Check from external machine:
   curl http://omis-pc.example.com
   telnet omis-pc.example.com 80
   telnet omis-pc.example.com 443
   ```

3. **Domain already has certificates elsewhere**
   - Let's Encrypt rate limits: 50 certificates per domain per week
   - Wait 1 hour and try again
   - Check: https://crt.sh/?q=omis-pc.example.com

4. **Caddy can't write to certificate storage**
   ```bash
   # Check volume permissions
   docker compose exec caddy ls -la /data
   # Should be writable by Caddy
   ```

### Issue: Mixed Content Warnings

**Symptom:**
Browser shows padlock but with warnings about "insecure content"

**Cause:**
Frontend is loading resources over HTTP instead of HTTPS

**Solution:**
Ensure all URLs in frontend code use relative paths or HTTPS:
```javascript
// Bad
const API_URL = 'http://omis-pc.example.com/api';

// Good
const API_URL = '/api';  // Relative to current protocol
// or
const API_URL = 'https://omis-pc.example.com/api';  // Explicit HTTPS
```

### Issue: WebSocket Connection Fails

**Symptom:**
Frontend can't connect to WebSocket after enabling HTTPS

**Cause:**
WebSocket URL still using `ws://` instead of `wss://`

**Solution:**
```bash
# Update .env
NEXT_PUBLIC_WS_BASE_URL=wss://omis-pc.example.com
# Rebuild frontend or restart containers
docker compose restart frontend
```

### Issue: Certificate Renewal Failed

**Symptom:**
Certificate expires (Caddy renews 30 days before expiry)

**Cause:**
- VM was offline during renewal
- DNS changed
- Port 80/443 blocked

**Solution:**
```bash
# Force certificate renewal
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile

# Check renewal logs
docker compose logs caddy | grep -i renew
```

---

## Without a Domain: Alternative Options

If you don't have a domain yet but need HTTPS:

### Option 1: Self-Signed Certificate (Not Recommended)

**Pros:**
- Free and immediate
- Provides encryption

**Cons:**
- Browser shows scary warnings
- Users must manually accept certificate
- No authentication (vulnerable to MITM)
- Not suitable for production

**How to implement:**
```bash
# Generate self-signed cert
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/omis-pc/certs/selfsigned.key \
  -out /opt/omis-pc/certs/selfsigned.crt

# Update Caddyfile to use it
# (Not recommended - use a domain instead)
```

### Option 2: Cloudflare Tunnel (Free)

**Pros:**
- Free HTTPS without owning a domain
- DDoS protection
- No open ports needed

**Cons:**
- Traffic routed through Cloudflare
- Requires Cloudflare account
- More complex setup

**How to implement:**
See: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/

### Option 3: ngrok (Development Only)

**Pros:**
- Instant HTTPS URL
- Great for testing/demos

**Cons:**
- Free tier has random URLs
- Session-based (URL changes on restart)
- Not for production

**How to implement:**
```bash
ngrok http 80
# Provides URL like: https://abc123.ngrok.io
```

### Option 4: nip.io / xip.io (Magic DNS)

**Pros:**
- Free domain that points to your IP
- Works with Let's Encrypt
- No DNS configuration needed

**Cons:**
- Relies on third-party service
- Less professional
- Service could go offline

**How to implement:**
```bash
# Your IP: 20.245.121.120
# Use domain: 20.245.121.120.nip.io

# Set in .env:
DOMAIN=20.245.121.120.nip.io
# Restart containers
docker compose up -d
```

---

## Security Best Practices

### 1. HSTS (HTTP Strict Transport Security)

Already configured in Caddyfile:
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

This tells browsers to ONLY connect via HTTPS for the next year.

### 2. Certificate Transparency

Let's Encrypt publishes all certificates to public logs. Check yours:
```
https://crt.sh/?q=omis-pc.example.com
```

### 3. Monitor Certificate Expiry

Caddy auto-renews, but set up monitoring anyway:
```bash
# Check current certificate expiry
echo | openssl s_client -servername omis-pc.example.com \
  -connect omis-pc.example.com:443 2>/dev/null | \
  openssl x509 -noout -dates
```

### 4. Disable Old TLS Versions

Caddy defaults to TLS 1.2 and 1.3 (secure). No action needed.

### 5. Use Strong Ciphers

Caddy automatically uses modern, secure cipher suites. No action needed.

---

## Environment Variable Reference

### Current Configuration (No Domain)

```bash
# .env file at /opt/omis-pc/.env

# No domain set
DOMAIN=

# HTTP URLs (no encryption)
WEB_CLIENT_BASE_URL=http://20.245.121.120:3000
NEXT_PUBLIC_API_BASE_URL=http://20.245.121.120:5000/api/v1/
NEXT_PUBLIC_WS_BASE_URL=ws://20.245.121.120:5001
```

### Future Configuration (With Domain)

```bash
# .env file at /opt/omis-pc/.env

# Domain configured
DOMAIN=omis-pc.example.com

# HTTPS URLs (encrypted)
WEB_CLIENT_BASE_URL=https://omis-pc.example.com
NEXT_PUBLIC_API_BASE_URL=https://omis-pc.example.com/api/v1/
NEXT_PUBLIC_WS_BASE_URL=wss://omis-pc.example.com
```

**When you update these:**
1. Edit `/opt/omis-pc/.env`
2. Run `docker compose up -d` (recreates containers with new env vars)
3. Caddy automatically detects domain change and provisions certificates

---

## Quick Reference Commands

```bash
# Check current TLS status
curl -I https://omis-pc.example.com

# View Caddy certificate info
docker compose exec caddy caddy list-certificates

# Force certificate renewal
docker compose exec caddy caddy reload

# View Caddy logs for TLS issues
docker compose logs caddy | grep -i certificate

# Test HTTPS is working
curl -v https://omis-pc.example.com

# Check certificate expiry
echo | openssl s_client -connect omis-pc.example.com:443 2>/dev/null | \
  openssl x509 -noout -dates

# Restart Caddy after .env changes
docker compose restart caddy
```

---

## Summary

| Stage | Access Method | Encryption | Action Needed |
|-------|---------------|------------|---------------|
| **Now (No Domain)** | `http://20.245.121.120` | ❌ None | Use for testing only |
| **After Domain Setup** | `https://omis-pc.example.com` | ✅ TLS 1.3 | Update .env, restart |
| **Production Ready** | `https://your-domain.com` | ✅ TLS 1.3 + HSTS | Monitor certificate expiry |

**Remember:**
- Caddy handles everything automatically once you set `DOMAIN`
- No manual certificate management needed
- Certificates renew automatically
- HTTP→HTTPS redirect is automatic
- Current setup works but is not secure for production
