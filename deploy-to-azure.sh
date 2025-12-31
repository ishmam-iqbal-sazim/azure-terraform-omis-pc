#!/bin/bash
set -e

# =============================================================================
# OMIS Product Configurator - Azure Deployment Script
# =============================================================================

# Get current infrastructure values from Terraform
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/projects/omis-pc/production"

echo "Fetching infrastructure values from Terraform..."
cd "$TERRAFORM_DIR"

# Get values from Terraform output
ACR_NAME="omispcacrprod"
ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server 2>/dev/null || echo "omispcacrprod.azurecr.io")
VM_IP=$(terraform output -raw vm_public_ip 2>/dev/null || echo "")
VM_USER="azureuser"
PRODUCT_CONFIGURATOR_DIR="/home/ishmamiqbal/Engineering/omis/product-configurator"

# Database Configuration
DB_HOST=$(terraform output -raw db_server_fqdn 2>/dev/null || echo "omis-pc-prod-db.postgres.database.azure.com")
DB_NAME=$(terraform output -raw db_name 2>/dev/null || echo "omis_pc_db")
DB_USER=$(terraform output -raw db_admin_username 2>/dev/null || echo "omispcadmin")
DB_PASSWORD="OmisPC2024!SecureProd"

# Validate we have required values
if [ -z "$VM_IP" ]; then
  echo "ERROR: Could not get VM IP from Terraform. Make sure 'terraform apply' was successful."
  exit 1
fi

echo "Using VM IP: $VM_IP"
echo "Using ACR: $ACR_LOGIN_SERVER"

echo "=========================================="
echo "OMIS Product Configurator - Azure Deployment"
echo "=========================================="

# Step 1: Login to Azure Container Registry
echo ""
echo "[1/5] Logging into Azure Container Registry..."
az acr login --name $ACR_NAME

# Step 2: Build and push frontend
echo ""
echo "[2/5] Building and pushing frontend image with environment variables..."
cd "$PRODUCT_CONFIGURATOR_DIR/frontend"

# Build with environment variables for Next.js
# NOTE: Replace 'your-openrouter-api-key-here' with your actual OpenRouter API key
docker build -f infra/dockerfiles/Dockerfile \
  --build-arg NEXT_PUBLIC_STAGE_ENV=production \
  --build-arg NEXT_PUBLIC_API_BASE_URL=http://${VM_IP}:5000/api/v1/ \
  --build-arg NEXT_PUBLIC_WS_BASE_URL=ws://${VM_IP}:5001 \
  --build-arg NEXT_PUBLIC_OPENROUTER_API_KEY=your-openrouter-api-key-here \
  -t $ACR_LOGIN_SERVER/omis-pc/fe:latest .
docker push $ACR_LOGIN_SERVER/omis-pc/fe:latest

# Step 3: Build and push backend
echo ""
echo "[3/5] Building and pushing backend image..."
cd "$PRODUCT_CONFIGURATOR_DIR/backend"
docker build -f infra/dockerfiles/Dockerfile -t $ACR_LOGIN_SERVER/omis-pc/be:latest .
docker push $ACR_LOGIN_SERVER/omis-pc/be:latest

# Step 4: Build and push csvtomdb
echo ""
echo "[4/5] Building and pushing csvtomdb image..."
cd "$PRODUCT_CONFIGURATOR_DIR/csv-to-mdb"
docker build -t $ACR_LOGIN_SERVER/omis-pc/csvtomdb-service:latest .
docker push $ACR_LOGIN_SERVER/omis-pc/csvtomdb-service:latest

# Step 5: Create .env file for VM
echo ""
echo "[5/5] Creating .env configuration..."

cat > /tmp/omis-pc.env << ENVEOF
# Container Registry
REGISTRY=omispcacrprod.azurecr.io

# Image Tags
FE_TAG=latest
BE_TAG=latest
CSV_TAG=latest

# Database Connection
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:5432/${DB_NAME}?sslmode=require

# Application Configuration
NODE_ENV=production
STAGE_ENV=production
BE_PORT=5000
BE_WS_PORT=5001

# JWT Configuration
JWT_SECRET=omis-pc-jwt-secret-production-2024
JWT_TOKEN_LIFETIME=24h

# URLs
WEB_CLIENT_BASE_URL=http://${VM_IP}:3000
API_HEALTH_URL=http://localhost:5000/api/health
SPRING_BACKEND_BASE_URL=http://csvtomdb:8080

# Frontend Environment
NEXT_PUBLIC_STAGE_ENV=production
NEXT_PUBLIC_API_BASE_URL=http://${VM_IP}:5000/api/v1/
NEXT_PUBLIC_WS_BASE_URL=ws://${VM_IP}:5001

# AI API Keys (replace with actual API keys)
ANTHROPIC_API_KEY=your-anthropic-api-key-here
OPENAI_API_KEY=your-openai-api-key-here
GEMINI_API_KEY=your-gemini-api-key-here
NEXT_PUBLIC_OPENROUTER_API_KEY=your-openrouter-api-key-here

# AI Models
ANTHROPIC_MODEL=claude-sonnet-4-5-20250929
GEMINI_MODEL=gemini-2.0-flash
OPENAI_MODEL=gpt-4.1-2025-04-14

# AWS S3 (update these for production if needed)
AWS_S3_REGION=us-east-1
AWS_S3_ENDPOINT=
AWS_S3_BUCKET_NAME=omis-pc-prod-bucket
AWS_S3_PRESIGN_URL_EXPIRY_IN_MINUTES=5
AWS_S3_BUCKET_URL=

# Other
ENABLE_AUDIT_LOGGING=true
ENVEOF

echo ""
echo "=========================================="
echo "Build complete! Images pushed to ACR."
echo "=========================================="

# Ask if user wants to deploy to VM automatically
echo ""
read -p "Do you want to deploy to the VM now? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "[6/7] Copying .env to VM..."

  # Ensure /opt/omis-pc directory exists on VM
  ssh $VM_USER@$VM_IP "sudo mkdir -p /opt/omis-pc && sudo chown $VM_USER:$VM_USER /opt/omis-pc"

  # Copy .env file
  scp /tmp/omis-pc.env $VM_USER@$VM_IP:/opt/omis-pc/.env

  echo ""
  echo "[7/7] Deploying on VM..."

  # Deploy on VM
  ssh $VM_USER@$VM_IP << 'EOSSH'
    cd /opt/omis-pc

    # Login to ACR (will use Azure CLI credentials)
    echo "Logging into Azure Container Registry..."
    az acr login --name omispcacrprod

    # Check if docker-compose.yml exists, if not, create a basic one
    if [ ! -f docker-compose.yml ]; then
      echo "Creating docker-compose.yml..."
      cat > docker-compose.yml << 'EOCOMPOSE'
version: '3.8'

services:
  frontend:
    image: ${REGISTRY}/omis-pc/fe:${FE_TAG}
    container_name: omis-pc-frontend
    ports:
      - "3000:3000"
    env_file:
      - .env
    restart: unless-stopped
    depends_on:
      - backend

  backend:
    image: ${REGISTRY}/omis-pc/be:${BE_TAG}
    container_name: omis-pc-backend
    ports:
      - "${BE_PORT}:5000"
      - "${BE_WS_PORT}:5001"
    env_file:
      - .env
    restart: unless-stopped
    depends_on:
      - csvtomdb

  csvtomdb:
    image: ${REGISTRY}/omis-pc/csvtomdb-service:${CSV_TAG}
    container_name: omis-pc-csvtomdb
    ports:
      - "8080:8080"
    env_file:
      - .env
    restart: unless-stopped
EOCOMPOSE
    fi

    # Pull and start services
    echo "Pulling latest images..."
    docker compose pull

    echo "Starting services..."
    docker compose up -d

    echo ""
    echo "Deployment complete! Services status:"
    docker compose ps
EOSSH

  echo ""
  echo "=========================================="
  echo "Deployment Complete!"
  echo "=========================================="
  echo ""
  echo "Application URLs:"
  echo "  Frontend:  http://$VM_IP:3000"
  echo "  Backend:   http://$VM_IP:5000"
  echo "  WebSocket: ws://$VM_IP:5001"
  echo ""
  echo "To view logs:"
  echo "  ssh $VM_USER@$VM_IP 'cd /opt/omis-pc && docker compose logs -f'"
  echo ""
  echo "=========================================="
else
  echo ""
  echo "=========================================="
  echo "Manual Deployment Steps"
  echo "=========================================="
  echo ""
  echo "1. Copy .env to VM:"
  echo "   scp /tmp/omis-pc.env $VM_USER@$VM_IP:/opt/omis-pc/.env"
  echo ""
  echo "2. SSH into VM:"
  echo "   ssh $VM_USER@$VM_IP"
  echo ""
  echo "3. On the VM, login to ACR and start services:"
  echo "   cd /opt/omis-pc"
  echo "   az acr login --name omispcacrprod"
  echo "   docker compose pull"
  echo "   docker compose up -d"
  echo ""
  echo "4. Verify services are running:"
  echo "   docker compose ps"
  echo "   docker compose logs -f"
  echo ""
  echo "=========================================="
  echo "Application URLs (after deployment):"
  echo "  Frontend:  http://$VM_IP:3000"
  echo "  Backend:   http://$VM_IP:5000"
  echo "  WebSocket: ws://$VM_IP:5001"
  echo "=========================================="
fi
