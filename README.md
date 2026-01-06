# Azure Terraform - OMIS Product Configurator

Infrastructure as Code for the OMIS Product Configurator application on Azure.

## Directory Structure

```
azure-terraform-omis-pc/
├── common/                              # Shared configuration files
│   └── cloud-init-azure.yaml.tpl        # Cloud-init template for VM setup
├── modules/                             # Reusable Terraform modules
│   └── azure/
│       ├── acr/                         # Azure Container Registry
│       ├── database/                    # PostgreSQL Flexible Server
│       ├── nsg/                         # Network Security Group
│       ├── vm/                          # Virtual Machine
│       └── vnet/                        # Virtual Network
├── projects/                            # Project-specific infrastructure
│   └── omis-pc/
│       └── production/                  # Production environment
└── README.md
```

## Modules

### VNet Module (`modules/azure/vnet`)
Creates a Virtual Network with configurable subnets.

### NSG Module (`modules/azure/nsg`)
Creates a Network Security Group with customizable security rules.

### VM Module (`modules/azure/vm`)
Creates a Linux Virtual Machine with:
- Public IP (Static)
- Network Interface
- NSG association
- Cloud-init support
- System-assigned managed identity

### Database Module (`modules/azure/database`)
Creates a PostgreSQL Flexible Server with:
- Database
- Azure services firewall rule
- Custom firewall rules

### ACR Module (`modules/azure/acr`)
Creates an Azure Container Registry for storing container images.

## Usage

### Production Environment

```bash
cd projects/omis-pc/production

# Copy example variables (if not already done)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Initialize Terraform
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply
```

### Adding a Development Environment

To add a development environment, copy the production folder and adjust variables:

```bash
cp -r projects/omis-pc/production projects/omis-pc/development
```

Then edit `development/variables.tf` to use smaller resource sizes:
- VM: `Standard_D2ps_v5` (2 vCPU, 8GB)
- DB SKU: `B_Standard_B1ms` (1 vCore, 2GB)
- DB Storage: 32GB
- ACR SKU: Basic

## Production Resources

| Resource | Specification |
|----------|---------------|
| VM Size | Standard_D2s_v3 (2 vCPU, 8GB RAM) |
| DB SKU | B_Standard_B2ms (2 vCores, 4GB) |
| DB Storage | 64GB |
| ACR SKU | Standard |
| Backup Retention | 14 days |
| VNet CIDR | 10.2.0.0/16 |

## Outputs

After applying, you'll get:
- `vm_public_ip` - Public IP of the VM
- `ssh_command` - SSH command to connect
- `db_server_fqdn` - Database FQDN
- `db_connection_string` - PostgreSQL connection string
- `acr_login_server` - ACR login URL
- `frontend_url` - Frontend application URL
- `backend_api_url` - Backend API URL
- `backend_websocket_url` - WebSocket URL

## Application Architecture

The VM runs Docker Compose with:
- **Frontend** (Next.js) - Port 3000
- **Backend** (Node.js) - Ports 5000 (HTTP), 5001 (WebSocket)
- **csvtomdb** (Java/Spring) - Port 8080 (internal only)

## Security

- SSH key-based authentication only
- iptables firewall with rate limiting
- NSG rules for granular port access
- Docker network isolation
- PostgreSQL firewall rules

## Destroying Infrastructure

To tear down the infrastructure:

```bash
cd projects/omis-pc/production
terraform destroy
```
