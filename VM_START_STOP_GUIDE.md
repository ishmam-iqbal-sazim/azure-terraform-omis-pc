# VM Start/Stop Operations Guide

This guide covers how to safely stop and start your Azure infrastructure for the OMIS Product Configurator.

---

## Current Infrastructure

| Resource | Name | Details |
|----------|------|---------|
| **VM** | `omis-pc-prod-vm` | Standard_D4ds_v6 (4 vCPUs, 16GB RAM, x64) |
| **Public IP** | `20.245.62.39` | Static (won't change when stopped) |
| **Database** | `omis-pc-prod-db` | PostgreSQL Flexible Server |
| **Resource Group** | `sazim-3dif-omis-pc-prod` | westus region |
| **ACR** | `omispcacrprod.azurecr.io` | Always available |

---

## Stopping Everything (End of Day)

### Option 1: Stop VM Only (Recommended for Daily Use)

This is the quickest option for overnight/weekend shutdowns:

```bash
# Stop the VM (stops billing for compute)
az vm deallocate --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm
```

**What happens:**
- ✅ VM stops (no compute charges)
- ✅ Docker containers stop automatically
- ✅ Public IP remains the same (20.245.62.39)
- ⚠️ Database continues running (and billing)
- ⚠️ Disk storage still incurs minimal charges

**Estimated savings:** ~$3-5/day for VM compute

---

### Option 2: Stop VM + Database (Maximum Savings)

For longer periods (weekends, vacations):

```bash
# Stop the VM
az vm deallocate --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm

# Stop the database
az postgres flexible-server stop --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-db
```

**What happens:**
- ✅ VM stops (no compute charges)
- ✅ Database stops (no compute charges)
- ✅ Public IP remains the same
- ⚠️ Storage still incurs minimal charges

**Estimated savings:** ~$5-8/day total

---

### Option 3: Using Azure Portal (GUI)

1. Go to [portal.azure.com](https://portal.azure.com)
2. Navigate to **Virtual Machines** → `omis-pc-prod-vm`
3. Click **Stop** button at the top
4. (Optional) Navigate to **Azure Database for PostgreSQL servers** → `omis-pc-prod-db` → Click **Stop**

---

## Starting Everything (Next Day)

### Start VM Only

```bash
# Start the VM
az vm start --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm
```

**What happens automatically:**
- ✅ VM boots up (takes ~30-60 seconds)
- ✅ Docker containers auto-start (configured with `restart: unless-stopped`)
- ✅ Frontend available at http://20.245.62.39:3000
- ✅ Backend available at http://20.245.62.39:5000
- ✅ All environment variables preserved
- ✅ Same IP address (20.245.62.39)

**Wait time:** 1-2 minutes for everything to be fully operational

---

### Start VM + Database

If you stopped the database:

```bash
# Start the database first
az postgres flexible-server start --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-db

# Then start the VM
az vm start --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm
```

**Wait time:** 2-3 minutes for everything to be fully operational

---

### Using Azure Portal (GUI)

1. Go to [portal.azure.com](https://portal.azure.com)
2. Navigate to **Virtual Machines** → `omis-pc-prod-vm`
3. Click **Start** button
4. (Optional) Navigate to **Azure Database for PostgreSQL servers** → `omis-pc-prod-db` → Click **Start**

---

## Verification After Startup

Once started, verify everything is running:

```bash
# Check VM status
az vm get-instance-view --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm --query instanceView.statuses[1]

# SSH into VM and check containers
ssh azureuser@20.245.62.39
cd /opt/omis-pc
docker compose ps
```

**Expected output:**
```
NAME       STATUS
frontend   Up X minutes
backend    Up X minutes
csvtomdb   Up X minutes
```

**Test the application:**
- Frontend: http://20.245.62.39:3000
- Backend Health: http://20.245.62.39:5000/health
- Backend API: http://20.245.62.39:5000/api/v1/

---

## Cost Breakdown

### While Running:
- **VM (Standard_D4ds_v6):** ~$120-150/month (~$4-5/day)
- **Database (B_Standard_B2ms):** ~$30-50/month (~$1-2/day)
- **Storage (64GB disk + DB):** ~$10-15/month
- **Network/ACR:** ~$5-10/month
- **Total:** ~$165-225/month

### While Stopped (Option 1 - VM only):
- **VM:** $0 (deallocated)
- **Database:** ~$30-50/month (still running)
- **Storage:** ~$10-15/month (disk remains)
- **Total:** ~$40-65/month

### While Stopped (Option 2 - VM + DB):
- **VM:** $0
- **Database:** $0
- **Storage:** ~$10-15/month (only disk storage)
- **Total:** ~$10-15/month

---

## Troubleshooting

### Problem: Containers don't auto-start

**Solution:**
```bash
ssh azureuser@20.245.62.39
cd /opt/omis-pc
docker compose up -d
```

### Problem: Frontend shows old cached version

**Solution:**
- Hard refresh browser: `Ctrl + Shift + R` (Windows/Linux) or `Cmd + Shift + R` (Mac)
- Or open incognito/private window

### Problem: Backend can't connect to database

**Possible causes:**
1. Database wasn't started
2. Database is still starting (wait 1-2 minutes)

**Solution:**
```bash
# Check database status
az postgres flexible-server show --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-db --query state

# If stopped, start it
az postgres flexible-server start --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-db
```

### Problem: Can't SSH into VM

**Possible causes:**
1. VM is still starting (wait 1-2 minutes)
2. SSH key mismatch

**Solution:**
```bash
# Check VM status
az vm get-instance-view --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm --query instanceView.statuses[1]

# If running but can't SSH, reset SSH key
az vm user update --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm --username azureuser --ssh-key-value "$(cat ~/.ssh/id_rsa.pub)"
```

---

## Quick Reference Commands

```bash
# Stop everything for the night
az vm deallocate --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm

# Start everything in the morning
az vm start --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm

# Check VM status
az vm list -d --output table --resource-group sazim-3dif-omis-pc-prod

# Check database status
az postgres flexible-server list --resource-group sazim-3dif-omis-pc-prod --output table

# SSH into VM
ssh azureuser@20.245.62.39

# View container status
ssh azureuser@20.245.62.39 "cd /opt/omis-pc && docker compose ps"

# View container logs
ssh azureuser@20.245.62.39 "cd /opt/omis-pc && docker compose logs -f"
```

---

## Automation (Optional)

You can automate daily shutdown/startup using Azure Automation or scheduled scripts.

### Example: Auto-shutdown at 8 PM daily

```bash
# This can be set up in Azure Portal under VM → Auto-shutdown
# Or using Azure CLI:
az vm auto-shutdown --resource-group sazim-3dif-omis-pc-prod --name omis-pc-prod-vm --time 2000
```

---

## Important Notes

- **Static IP:** Your IP `20.245.62.39` is static and won't change when you stop/start
- **Data Persistence:** All data in the database and container volumes persists through stop/start
- **Docker Auto-restart:** Containers are configured with `restart: unless-stopped`, so they auto-start with the VM
- **No Data Loss:** Stopping the VM does NOT delete any data
- **Billing:** You're only charged for what's running. Stopped resources (except storage) don't incur compute charges

---

## Security Reminder

Since your routes are not protected, **always stop the VM when not in use** to prevent unauthorized access.

Consider implementing:
1. Network Security Group (NSG) rules to restrict access by IP
2. Azure Firewall
3. Authentication middleware on all routes
4. HTTPS with proper certificates
5. Azure Private Link for database

---

## Related Documentation

- [DEPLOYMENT_WORKFLOW.md](./DEPLOYMENT_WORKFLOW.md) - How to deploy application updates
- [INFRASTRUCTURE_GUIDE.md](./INFRASTRUCTURE_GUIDE.md) - Complete infrastructure overview
- [README.md](./README.md) - Project overview and getting started

---

**Last Updated:** December 31, 2025
**Infrastructure Version:** Production v1.0
