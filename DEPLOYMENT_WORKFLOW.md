# Deployment Workflow (After Infrastructure is Created)

Once `terraform apply` completes, your infrastructure exists. But the application isn't running yet. Here's the complete deployment workflow.

---

## Current Production Environment

| Resource | Value |
|----------|-------|
| VM Public IP | `20.245.121.120` |
| SSH Command | `ssh azureuser@20.245.121.120` |
| ACR Login Server | `omispcacrprod.azurecr.io` |
| DB Host | `omis-pc-prod-db.postgres.database.azure.com` |
| DB Name | `omis_pc_db` |
| DB User | `omispcadmin` |

---

## Step 1: Get Connection Information

After Terraform completes, it outputs important information:

```bash
# Run this to see outputs
cd /home/ishmamiqbal/Engineering/infra/azure-terraform-omis-pc/projects/omis-pc/production
terraform output

# You'll see:
# vm_public_ip = "20.245.121.120"
# ssh_command = "ssh azureuser@20.245.121.120"
# acr_login_server = "omispcacrprod.azurecr.io"
# db_connection_string = "postgresql://omispcadmin@omis-pc-prod-db.postgres..."
```

---

## Step 2: Build and Push Docker Images

On your development machine:

```bash
# 1. Login to Azure Container Registry
az acr login --name omispcacrprod

# 2. Navigate to product configurator directory
cd /home/ishmamiqbal/Engineering/omis/product-configurator

# 3. Build frontend (note: uses Dockerfile in infra/dockerfiles/)
cd frontend
docker build -f infra/dockerfiles/Dockerfile -t omispcacrprod.azurecr.io/omis-pc/fe:latest .
docker push omispcacrprod.azurecr.io/omis-pc/fe:latest

# 4. Build backend (note: uses Dockerfile in infra/dockerfiles/)
cd ../backend
docker build -f infra/dockerfiles/Dockerfile -t omispcacrprod.azurecr.io/omis-pc/be:latest .
docker push omispcacrprod.azurecr.io/omis-pc/be:latest

# 5. Build csvtomdb (Dockerfile is in root of csv-to-mdb)
cd ../csv-to-mdb
docker build -t omispcacrprod.azurecr.io/omis-pc/csvtomdb-service:latest .
docker push omispcacrprod.azurecr.io/omis-pc/csvtomdb-service:latest
```

**Or use the deployment script:**

```bash
chmod +x /home/ishmamiqbal/Engineering/infra/azure-terraform-omis-pc/deploy-to-azure.sh
/home/ishmamiqbal/Engineering/infra/azure-terraform-omis-pc/deploy-to-azure.sh
```

---

## Step 3: SSH into the VM

```bash
# Connect to your VM
ssh azureuser@20.245.121.120

# You're now inside the VM!
```

---

## Step 4: Create the .env File (IMPORTANT)

The `.env` file must be created properly for docker-compose to read it. **Do not copy from .env.example** - create it directly:

```bash
# Navigate to app directory
cd /opt/omis-pc

# Create the .env file with all required variables
cat > /opt/omis-pc/.env << 'EOF'
# =============================================================================
# Container Registry Configuration
# =============================================================================
REGISTRY=omispcacrprod.azurecr.io

# Image Tags
FE_TAG=latest
BE_TAG=latest
CSV_TAG=latest

# =============================================================================
# Application Configuration
# =============================================================================
NODE_ENV=production
STAGE_ENV=production

# Backend Ports
BE_PORT=5000
BE_WS_PORT=5001

# Internal Service URLs
API_HEALTH_URL=http://localhost:5000/api/health
SPRING_BACKEND_BASE_URL=http://csvtomdb:8080

# =============================================================================
# Database Configuration
# =============================================================================
DATABASE_URL=postgresql://omispcadmin:OmisPC2024!SecureProd@omis-pc-prod-db.postgres.database.azure.com:5432/omis_pc_db?sslmode=require

# =============================================================================
# JWT Configuration
# =============================================================================
JWT_SECRET=omis-pc-production-jwt-secret-change-this-in-prod
JWT_TOKEN_LIFETIME=24h

# =============================================================================
# URLs
# =============================================================================
WEB_CLIENT_BASE_URL=http://20.245.121.120:3000

# Frontend Environment Variables
NEXT_PUBLIC_STAGE_ENV=production
NEXT_PUBLIC_API_BASE_URL=http://20.245.121.120:5000/api/v1/
NEXT_PUBLIC_WS_BASE_URL=ws://20.245.121.120:5001
NEXT_PUBLIC_GOOGLE_CLIENT_ID=your-actual-google-client-id
NEXT_PUBLIC_OPENROUTER_API_KEY=your-openrouter-api-key-here

# =============================================================================
# AI API Keys (Replace with your actual API keys)
# =============================================================================
ANTHROPIC_API_KEY=your-anthropic-api-key-here
OPENAI_API_KEY=your-openai-api-key-here
GEMINI_API_KEY=your-gemini-api-key-here

# AI Models
ANTHROPIC_MODEL=claude-sonnet-4-5-20250929
GEMINI_MODEL=gemini-2.0-flash
OPENAI_MODEL=gpt-4.1-2025-04-14

# =============================================================================
# AWS S3 Configuration (update for production)
# =============================================================================
AWS_S3_REGION=us-east-1
AWS_S3_ENDPOINT=
AWS_S3_BUCKET_NAME=omis-pc-prod-bucket
AWS_S3_PRESIGN_URL_EXPIRY_IN_MINUTES=5
AWS_S3_BUCKET_URL=

# =============================================================================
# Email Configuration
# =============================================================================
SENDGRID_API_KEY=SG.xxxxxx
SEND_FROM_EMAIL=noreply@yourdomain.com

# =============================================================================
# Other Services
# =============================================================================
DOCUSEAL_API_KEY=string

GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret

ENABLE_AUDIT_LOGGING=true

# =============================================================================
# csvtomdb Service Configuration
# =============================================================================
SPRING_PROFILES_ACTIVE=production
SERVER_PORT=8080
EOF
```

**Verify the .env file was created correctly:**

```bash
# Check first few lines
cat /opt/omis-pc/.env | head -10

# Should show:
# # =============================================================================
# # Container Registry Configuration
# # =============================================================================
# REGISTRY=omispcacrprod.azurecr.io
# ...
```

---

## Step 5: Login to ACR from VM

```bash
# Login to Azure
az login

# Login to ACR
az acr login --name omispcacrprod
```

---

## Step 6: Start the Application

```bash
cd /opt/omis-pc

# Pull latest images
docker compose pull

# Start all services
docker compose up -d

# Check if running
docker compose ps

# View logs
docker compose logs -f
```

---

## Step 7: Verify Everything Works

```bash
# Check frontend (from VM)
curl http://localhost:3000

# Check backend health (from VM)
curl http://localhost:5000/api/health

# Check from internet (from your laptop)
curl http://20.245.121.120:3000
curl http://20.245.121.120:5000/api/health
```

---

## Complete Deployment Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DEPLOYMENT WORKFLOW                                   │
│                                                                              │
│   DEVELOPER'S LAPTOP                          AZURE                          │
│   ──────────────────                          ─────                          │
│                                                                              │
│   ┌─────────────────┐                                                        │
│   │  1. Code Change │                                                        │
│   └────────┬────────┘                                                        │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐     docker push      ┌─────────────────┐              │
│   │  2. Build Image │ ──────────────────►  │       ACR       │              │
│   │  docker build   │                      │  (Image Store)  │              │
│   └─────────────────┘                      └────────┬────────┘              │
│                                                     │                        │
│                                                     │ docker pull            │
│                                                     │                        │
│                                                     ▼                        │
│                                            ┌─────────────────┐              │
│   ┌─────────────────┐      SSH             │       VM        │              │
│   │  3. Deploy      │ ──────────────────►  │                 │              │
│   │  ./deploy.sh    │                      │  docker compose │              │
│   └─────────────────┘                      │       up        │              │
│                                            └────────┬────────┘              │
│                                                     │                        │
│                                                     │ SQL queries            │
│                                                     │                        │
│                                                     ▼                        │
│                                            ┌─────────────────┐              │
│                                            │   PostgreSQL    │              │
│                                            │    Database     │              │
│                                            └─────────────────┘              │
│                                                                              │
│   ┌─────────────────┐                      ┌─────────────────┐              │
│   │  4. User Access │ ──────────────────►  │    Frontend     │              │
│   │  Browser        │     HTTP :3000       │    (Next.js)    │              │
│   └─────────────────┘                      └─────────────────┘              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Using the Deploy Script

The VM has a deploy script for easier updates:

```bash
cd /opt/omis-pc

# Deploy a specific service with a specific tag
./deploy.sh frontend v1.2.0
./deploy.sh backend v1.2.0
./deploy.sh csvtomdb v1.0.5

# Deploy all services
./deploy.sh all latest
```

---

## Updating the Application

When you make code changes:

```bash
# On your laptop:
# 1. Build new image with new tag
cd /home/ishmamiqbal/Engineering/omis/product-configurator/frontend
docker build -f infra/dockerfiles/Dockerfile -t omispcacrprod.azurecr.io/omis-pc/fe:v1.2.1 .
docker push omispcacrprod.azurecr.io/omis-pc/fe:v1.2.1

# 2. SSH to VM and deploy
ssh azureuser@20.245.121.120
cd /opt/omis-pc
./deploy.sh frontend v1.2.1
```

---

## Troubleshooting

### Issue: "The REGISTRY variable is not set"

If you see this warning:
```
WARN[0000] The "REGISTRY" variable is not set. Defaulting to a blank string.
```

**Cause**: The `.env` file is missing, empty, or not readable by docker-compose.

**Solution**:
```bash
# Check if .env exists and has content
cat /opt/omis-pc/.env | head -5

# If empty or missing, recreate it using Step 4 above
```

### Issue: "invalid reference format"

**Cause**: The REGISTRY variable is blank, causing image names like `/omis-pc/fe:latest` instead of `omispcacrprod.azurecr.io/omis-pc/fe:latest`.

**Solution**: Ensure `.env` file exists and contains `REGISTRY=omispcacrprod.azurecr.io`

### Issue: docker-compose.yml version warning

If you see:
```
WARN[0000] /opt/omis-pc/docker-compose.yml: the attribute `version` is obsolete
```

This is just a warning and can be ignored. The `version` attribute is no longer required in modern Docker Compose.

### Common Troubleshooting Commands

```bash
# View running containers
docker ps

# View all containers (including stopped)
docker ps -a

# View logs for a specific service
docker compose logs frontend
docker compose logs backend
docker compose logs csvtomdb

# Follow logs in real-time
docker compose logs -f

# Restart a service
docker compose restart backend

# Stop everything
docker compose down

# Start everything
docker compose up -d

# Rebuild and restart
docker compose up -d --force-recreate

# Check disk space
df -h

# Check memory usage
free -h

# Check running processes
htop

# Check .env is being read
docker compose config
```

### Issue: Container exits immediately

Check the logs:
```bash
docker compose logs <service-name>
```

Common causes:
- Missing environment variables
- Database connection issues
- Port conflicts

### Issue: Cannot connect to database

1. Check the DATABASE_URL in .env
2. Verify the VM's IP is allowed in the database firewall (Terraform handles this)
3. Test connection:
```bash
# Install psql if needed
sudo apt-get install postgresql-client

# Test connection
psql "postgresql://omispcadmin:OmisPC2024!SecureProd@omis-pc-prod-db.postgres.database.azure.com:5432/omis_pc_db?sslmode=require"
```

---

## Application URLs

After successful deployment:

| Service | URL |
|---------|-----|
| Frontend | http://20.245.121.120:3000 |
| Backend API | http://20.245.121.120:5000 |
| Backend Health | http://20.245.121.120:5000/api/health |
| WebSocket | ws://20.245.121.120:5001 |

---

## Quick Reference: Full Deployment from Scratch

```bash
# === ON YOUR LAPTOP ===

# 1. Build and push images
az acr login --name omispcacrprod

cd /home/ishmamiqbal/Engineering/omis/product-configurator

# Frontend
cd frontend
docker build -f infra/dockerfiles/Dockerfile -t omispcacrprod.azurecr.io/omis-pc/fe:latest .
docker push omispcacrprod.azurecr.io/omis-pc/fe:latest

# Backend
cd ../backend
docker build -f infra/dockerfiles/Dockerfile -t omispcacrprod.azurecr.io/omis-pc/be:latest .
docker push omispcacrprod.azurecr.io/omis-pc/be:latest

# csvtomdb
cd ../csv-to-mdb
docker build -t omispcacrprod.azurecr.io/omis-pc/csvtomdb-service:latest .
docker push omispcacrprod.azurecr.io/omis-pc/csvtomdb-service:latest

# === ON THE VM ===

# 2. SSH to VM
ssh azureuser@20.245.121.120

# 3. Create .env (see Step 4 above for full content)
cd /opt/omis-pc
# ... create .env file ...

# 4. Login and deploy
az login
az acr login --name omispcacrprod
docker compose pull
docker compose up -d

# 5. Verify
docker compose ps
curl http://localhost:3000
```
