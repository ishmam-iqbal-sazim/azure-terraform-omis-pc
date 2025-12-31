# Understanding Cloud Infrastructure: From Zero to Deep

A comprehensive guide for software developers who want to understand cloud infrastructure, written for the OMIS Product Configurator project.

---

## Table of Contents

1. [The 30,000-Foot View](#part-1-the-30000-foot-view)
2. [What Makes a Computer? (Hardware 101)](#part-2-what-makes-a-computer-hardware-101)
3. [Networking 101 (How Computers Talk)](#part-3-networking-101-how-computers-talk)
4. [What is a VNet? (Virtual Network)](#part-4-what-is-a-vnet-virtual-network)
5. [What is an NSG? (Network Security Group)](#part-5-what-is-an-nsg-network-security-group)
6. [What is a NIC? (Network Interface Card)](#part-6-what-is-a-nic-network-interface-card)
7. [What is a PIP? (Public IP)](#part-7-what-is-a-pip-public-ip)
8. [What is an OS Disk?](#part-8-what-is-an-os-disk)
9. [What is ACR? (Azure Container Registry)](#part-9-what-is-acr-azure-container-registry)
10. [What is the Database Module?](#part-10-what-is-the-database-module)
11. [What is the VM Module?](#part-11-what-is-the-vm-module)
12. [What is Cloud-Init?](#part-12-what-is-cloud-init)
13. [How It All Connects](#part-13-how-it-all-connects)
14. [Why Modules?](#part-14-why-modules)
15. [The Complete Terraform Flow](#part-15-the-complete-terraform-flow)
16. [Quick Reference - All Components](#part-16-quick-reference---all-components)

> **Note**: For deployment steps after infrastructure is created, see [DEPLOYMENT_WORKFLOW.md](./DEPLOYMENT_WORKFLOW.md)

---

## Part 1: The 30,000-Foot View

### What Are We Actually Trying to Do?

You built the **OMIS Product Configurator** - an application with:
- **Frontend** (Next.js) - The UI users see in their browser
- **Backend** (Node.js) - The API that handles business logic
- **csvtomdb service** (Java) - Converts CSV files to database format
- **PostgreSQL Database** - Stores all the data

Right now, this probably runs on your laptop when you do `npm run dev`.

**The Problem**: Your laptop can't serve real users because:
- It's not online 24/7
- It doesn't have a permanent internet address
- It can't handle many users
- If your laptop dies, the app dies

**The Solution**: Run it on a computer in Azure's data center that:
- Is online 24/7
- Has a permanent internet address
- Is secure and managed
- Can be recreated if it dies

**This repository = The blueprint for that computer and everything around it.**

### The One-Sentence Summary

> **This repository contains instructions (written in Terraform code) that tell Azure: "Build me a mini data center with a computer, a database, a private network, security walls, and a place to store my app's container images."**

---

## Part 2: What Makes a Computer? (Hardware 101)

Before understanding cloud, let's understand what a computer actually is.

### The Physical Parts

```
┌─────────────────────────────────────────────────────────────┐
│                        COMPUTER                              │
│                                                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐   │
│  │   CPU   │    │   RAM   │    │  DISK   │    │   NIC   │   │
│  │ (Brain) │    │(Memory) │    │(Storage)│    │(Network)│   │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘   │
│                                                              │
│  CPU: Executes instructions (like running your Node.js)     │
│  RAM: Temporary fast memory (holds running programs)         │
│  Disk: Permanent storage (holds files, OS, database)        │
│  NIC: Network Interface Card (connects to internet)          │
└─────────────────────────────────────────────────────────────┘
```

**Analogy - The Office Worker**:
| Component | Analogy | Purpose |
|-----------|---------|---------|
| **CPU** | The worker's brain | Does the thinking/work |
| **RAM** | The worker's desk | Holds what they're currently working on |
| **Disk** | The filing cabinet | Stores everything permanently |
| **NIC** | The phone/mailbox | Communicates with outside world |

When you write code, the CPU executes it, RAM holds it while running, Disk stores the files, and NIC sends responses to users.

### What is a Virtual Machine (VM)?

Azure doesn't give you a physical computer. They give you a **Virtual Machine**.

```
┌─────────────────────────────────────────────────────────────┐
│           AZURE'S GIANT PHYSICAL SERVER                      │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │    VM 1      │  │    VM 2      │  │    VM 3      │       │
│  │  (Your app)  │  │ (Someone's)  │  │ (Someone's)  │       │
│  │              │  │              │  │              │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
│  One physical machine pretends to be MANY separate machines │
└─────────────────────────────────────────────────────────────┘
```

A VM is like an apartment in an apartment building:
- You get your own private space
- You share the building's infrastructure (electricity, plumbing)
- Your neighbors can't enter your apartment
- You don't maintain the building - the landlord does

**In our repo**: `modules/azure/vm/` creates this virtual computer.

---

## Part 3: Networking 101 (How Computers Talk)

This is where most confusion happens. Let's build understanding layer by layer.

### IP Addresses: The Postal System of the Internet

Every device on a network needs an address, just like every house needs a postal address.

```
┌─────────────────────────────────────────────────────────────┐
│                     IP ADDRESSES                             │
│                                                              │
│  Private IP (Inside your network only)                       │
│  ─────────────────────────────────────                       │
│  Like apartment numbers: "Apt 101", "Apt 102"                │
│  Only meaningful INSIDE the building                         │
│  Examples: 10.0.0.5, 192.168.1.100                           │
│                                                              │
│  Public IP (Visible on the internet)                         │
│  ─────────────────────────────────────                       │
│  Like street addresses: "123 Main St, NYC"                   │
│  Anyone in the world can find you                            │
│  Examples: 52.160.10.21, 20.40.100.10                        │
└─────────────────────────────────────────────────────────────┘
```

**Why both?**

When a user types `http://your-app.com`:
1. DNS translates it to your **Public IP** (e.g., `52.160.10.21`)
2. The request arrives at Azure's edge
3. Azure routes it to your VM's **Private IP** (e.g., `10.2.1.4`)

### Ports: Doors on a Computer

A computer is like a building with many doors (ports). Each service uses a different door.

```
┌─────────────────────────────────────────────────────────────┐
│                      YOUR VM                                 │
│                                                              │
│   Port 22    Port 80    Port 443   Port 3000   Port 5000    │
│   ┌─────┐    ┌─────┐    ┌─────┐    ┌─────┐     ┌─────┐      │
│   │ SSH │    │HTTP │    │HTTPS│    │ FE  │     │ BE  │      │
│   │Door │    │Door │    │Door │    │Door │     │Door │      │
│   └─────┘    └─────┘    └─────┘    └─────┘     └─────┘      │
│                                                              │
│   22 = Admin login (SSH)                                     │
│   80 = Normal web traffic                                    │
│   443 = Secure web traffic                                   │
│   3000 = Your Next.js frontend                               │
│   5000 = Your Node.js backend API                            │
│   5001 = Your WebSocket server                               │
└─────────────────────────────────────────────────────────────┘
```

When a user goes to `http://52.160.10.21:3000`, they're saying:
> "Go to building at address 52.160.10.21, knock on door 3000"

### Common Ports Reference

| Port | Protocol | What It's For |
|------|----------|---------------|
| 22 | SSH | Remote server login (admin access) |
| 80 | HTTP | Normal web traffic |
| 443 | HTTPS | Secure web traffic |
| 3000 | - | Our Next.js frontend |
| 5000 | - | Our Node.js backend API |
| 5001 | - | Our WebSocket server |
| 5432 | PostgreSQL | Database connections |
| 8080 | - | Our csvtomdb service (internal) |

---

## Part 4: What is a VNet? (Virtual Network)

### The Problem VNet Solves

Imagine Azure's data center has millions of VMs from different customers. Without separation:
- Someone else's VM could accidentally (or maliciously) talk to yours
- Traffic would be chaos
- No security boundaries

### VNet = Your Private Network in the Cloud

**Analogy: A Gated Community**

```
┌─────────────────────────────────────────────────────────────┐
│                    AZURE DATA CENTER                         │
│                    (The whole city)                          │
│                                                              │
│   ┌─────────────────────────────────┐                        │
│   │      YOUR VNET (10.2.0.0/16)    │   Other customers'     │
│   │      (Your gated community)      │   VNets (separate)     │
│   │                                  │                        │
│   │   ┌──────────┐  ┌──────────┐    │   ┌──────────┐         │
│   │   │ Your VM  │  │  Future  │    │   │ Someone  │         │
│   │   │ 10.2.1.4 │  │  VM here │    │   │  else's  │         │
│   │   └──────────┘  └──────────┘    │   │   VM     │         │
│   │                                  │   └──────────┘         │
│   │   Gate: Only approved traffic   │                        │
│   └─────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

**What `10.2.0.0/16` means**:
- This is CIDR notation (a way to define IP ranges)
- `/16` means: "I get 65,536 IP addresses"
- Range: `10.2.0.0` to `10.2.255.255`
- All private (not internet-visible)

**In our repo** (`modules/azure/vnet/main.tf`):
```hcl
resource "azurerm_virtual_network" "this" {
  name          = var.name                    # "omis-pc-prod-vnet"
  address_space = var.address_space           # ["10.2.0.0/16"]
  location      = var.location                # "westus"
  ...
}
```

This tells Azure: "Create a private network with 65,536 addresses, isolated from everyone else."

### Subnet: Rooms Within the Gated Community

A VNet can be subdivided into **Subnets**.

**Why?** Different parts of your application have different security needs:
- Web servers might be internet-facing
- Databases should NEVER be internet-facing
- Internal services don't need public access

```
┌─────────────────────────────────────────────────────────────┐
│                   YOUR VNET (10.2.0.0/16)                    │
│                                                              │
│   ┌─────────────────────┐    ┌─────────────────────┐        │
│   │   VM Subnet          │    │   DB Subnet         │        │
│   │   (10.2.1.0/24)      │    │   (10.2.2.0/24)     │        │
│   │                      │    │                     │        │
│   │   256 IPs available  │    │   256 IPs available │        │
│   │   Can access internet│    │   NO internet access│        │
│   │                      │    │                     │        │
│   │   ┌────────────┐     │    │   ┌────────────┐    │        │
│   │   │  Your VM   │     │    │   │  Database  │    │        │
│   │   │  10.2.1.4  │     │    │   │  10.2.2.10 │    │        │
│   │   └────────────┘     │    │   └────────────┘    │        │
│   └─────────────────────┘    └─────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

**In our repo**, we create one subnet:
```hcl
subnets = [
  {
    name             = "omis-pc-prod-vm-subnet"
    address_prefixes = ["10.2.1.0/24"]    # 256 IPs
  }
]
```

### VNet Summary

| Component | Real-World Analogy | What It Does |
|-----------|-------------------|--------------|
| VNet | Gated community | Isolates your network from others |
| Address Space | Community boundaries | Defines how many addresses you have |
| Subnet | Buildings in community | Separates different zones with different rules |

---

## Part 5: What is an NSG? (Network Security Group)

### The Problem NSG Solves

You have a VM with many ports (doors). By default, should everyone be allowed to knock on any door?

**NO!** That's a security nightmare.

### NSG = The Security Guard with a Checklist

**Analogy**: Think of NSG as a bouncer at a club with a guest list.

```
┌─────────────────────────────────────────────────────────────┐
│                         NSG                                  │
│                  (Security Guard)                            │
│                                                              │
│   CHECKLIST (Rules):                                         │
│   ──────────────────                                         │
│   ✅ Port 22 (SSH): ALLOW from anywhere                      │
│   ✅ Port 80 (HTTP): ALLOW from anywhere                     │
│   ✅ Port 443 (HTTPS): ALLOW from anywhere                   │
│   ✅ Port 3000 (Frontend): ALLOW from anywhere               │
│   ✅ Port 5000 (Backend): ALLOW from anywhere                │
│   ✅ Port 5001 (WebSocket): ALLOW from anywhere              │
│   ❌ Everything else: DENY                                   │
│                                                              │
│   Each request is checked against this list.                 │
│   If no rule matches → DENIED by default.                    │
└─────────────────────────────────────────────────────────────┘
```

### Why is NSG Important?

**Without NSG**:
- Hackers could scan all 65,535 ports
- Your database port might be exposed
- Internal services could be attacked
- No control over who accesses what

**With NSG**:
- Only explicitly allowed traffic gets through
- Everything else is automatically blocked
- You control exactly who can access what

### NSG Rule Anatomy

Each rule has these parts:

| Property | What It Means | Example |
|----------|---------------|---------|
| `name` | Human-readable name | "SSH" |
| `priority` | Order checked (lower = first) | 1000 |
| `direction` | Inbound or Outbound | "Inbound" |
| `access` | Allow or Deny | "Allow" |
| `protocol` | TCP, UDP, or * | "Tcp" |
| `source_port_range` | Where traffic comes from | "*" (any) |
| `destination_port_range` | Which port on your VM | "22" |
| `source_address_prefix` | Who can send traffic | "*" (anyone) |
| `destination_address_prefix` | Who receives | "*" |

**In our repo** (`projects/omis-pc/production/main.tf`):
```hcl
security_rules = [
  {
    name                   = "SSH"
    priority               = 1000        # Lower = checked first
    direction              = "Inbound"   # Traffic coming IN
    access                 = "Allow"     # Let it through
    protocol               = "Tcp"
    destination_port_range = "22"        # SSH door
    source_address_prefix  = "*"         # From anywhere
    ...
  },
  {
    name                   = "Frontend"
    priority               = 1010
    destination_port_range = "3000"      # Next.js door
    ...
  },
  # ... more rules
]
```

### NSG Can Attach to Two Places

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│   Option 1: NSG on Subnet                                    │
│   ─────────────────────                                      │
│   Protects ALL VMs in that subnet                            │
│   Like a guard at the building entrance                      │
│                                                              │
│   Option 2: NSG on NIC (Network Interface)                   │
│   ───────────────────────────────────────                    │
│   Protects ONE specific VM                                   │
│   Like a guard at your apartment door                        │
│                                                              │
│   We do BOTH for defense in depth!                           │
└─────────────────────────────────────────────────────────────┘
```

**In our repo**, we create both associations:
```hcl
# Guard at building entrance
resource "azurerm_subnet_network_security_group_association" "vm_subnet" {
  subnet_id                 = module.vnet.subnet_ids[local.subnet_name]
  network_security_group_id = module.nsg.nsg_id
}

# Guard at apartment door
resource "azurerm_network_interface_security_group_association" "vm_nic" {
  network_interface_id      = module.vm.nic_id
  network_security_group_id = module.nsg.nsg_id
}
```

---

## Part 6: What is a NIC? (Network Interface Card)

### The Physical Concept

In a physical computer, the NIC is a hardware card that:
- Plugs into the motherboard
- Has an Ethernet port (where you plug the network cable)
- Has a unique MAC address
- Handles all network communication

**Analogy**: The NIC is like the mailbox of your house. All mail (network traffic) goes through it.

### Virtual NIC in Azure

In Azure, a NIC is a virtual version of this:

```
┌─────────────────────────────────────────────────────────────┐
│                         NIC                                  │
│              (Network Interface Card)                        │
│                                                              │
│   What it connects:                                          │
│   ─────────────────                                          │
│                                                              │
│   ┌─────────────┐                                            │
│   │   Subnet    │ ◄──── Which network segment                │
│   │ (10.2.1.0)  │       (gives private IP: 10.2.1.4)        │
│   └─────────────┘                                            │
│          │                                                   │
│          ▼                                                   │
│   ┌─────────────┐                                            │
│   │     NIC     │ ◄──── The connector                        │
│   └─────────────┘                                            │
│          │                                                   │
│          ▼                                                   │
│   ┌─────────────┐                                            │
│   │  Public IP  │ ◄──── Optional: internet address           │
│   │(52.160.10.21)│      (attached to NIC)                    │
│   └─────────────┘                                            │
│          │                                                   │
│          ▼                                                   │
│   ┌─────────────┐                                            │
│   │     VM      │ ◄──── The computer that uses this NIC      │
│   └─────────────┘                                            │
└─────────────────────────────────────────────────────────────┘
```

### Why NIC is Explicit in Azure

Azure doesn't assume what you want. The NIC is explicit because:
- A VM might need multiple NICs (for different networks)
- Each NIC can have different security rules
- Public IP is optional (some VMs don't need internet access)
- You might want to move a NIC between VMs

### NIC Properties

| Property | What It Does |
|----------|--------------|
| `subnet_id` | Which subnet this NIC belongs to |
| `private_ip_address_allocation` | Dynamic (auto-assign) or Static (you choose) |
| `public_ip_address_id` | Optional: attach a public IP |

**In our repo** (`modules/azure/vm/main.tf`):
```hcl
resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"    # "omis-pc-prod-vm-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id              # Connect to subnet
    private_ip_address_allocation = "Dynamic"                  # Auto-assign IP
    public_ip_address_id          = azurerm_public_ip.this.id  # Attach public IP
  }
}
```

---

## Part 7: What is a PIP? (Public IP)

### The Problem

Your VM has a private IP (e.g., `10.2.1.4`) that only exists inside your VNet.

Users on the internet can't reach `10.2.1.4` - it's not a valid internet address.

### PIP = Your Internet Address

**Analogy**:
- Private IP = Your apartment number (only meaningful inside the building)
- Public IP = Your street address (anyone in the world can find you)

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│   INTERNET                                                   │
│      │                                                       │
│      │  User requests: http://52.160.10.21:3000             │
│      │                                                       │
│      ▼                                                       │
│   ┌──────────────────┐                                       │
│   │    PUBLIC IP     │                                       │
│   │   52.160.10.21   │  ◄── Internet-visible address         │
│   └────────┬─────────┘                                       │
│            │                                                 │
│            │  Azure routes traffic                           │
│            │                                                 │
│            ▼                                                 │
│   ┌──────────────────┐                                       │
│   │       NIC        │                                       │
│   │  Private: 10.2.1.4│                                      │
│   └────────┬─────────┘                                       │
│            │                                                 │
│            ▼                                                 │
│   ┌──────────────────┐                                       │
│   │        VM        │                                       │
│   │   Your app here  │                                       │
│   └──────────────────┘                                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Static vs Dynamic IP

| Type | Behavior | Use Case |
|------|----------|----------|
| **Static** | IP never changes | Production servers |
| **Dynamic** | IP might change on restart | Dev/test environments |

For production, we use **Static** so your IP never changes (important for DNS).

**In our repo** (`modules/azure/vm/main.tf`):
```hcl
resource "azurerm_public_ip" "this" {
  name                = "${var.name}-pip"    # "omis-pc-prod-vm-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"              # IP never changes
  sku                 = "Standard"            # Required for Static
}
```

### Why "PIP"?

- **P**ublic **IP** = **PIP**
- It's just Azure's shorthand naming convention
- You'll see it in resource names: `omis-pc-prod-vm-pip`

---

## Part 8: What is an OS Disk?

### The Concept

Every computer needs a hard drive to store:
- The operating system (Linux/Windows)
- System files
- Your application files
- Logs and temporary data

### OS Disk = The VM's Hard Drive

```
┌─────────────────────────────────────────────────────────────┐
│                       OS DISK                                │
│                  (Virtual Hard Drive)                        │
│                                                              │
│   ┌─────────────────────────────────────────────────────┐   │
│   │                                                      │   │
│   │   /                     (root)                       │   │
│   │   ├── bin/              (system programs)            │   │
│   │   ├── etc/              (configuration)              │   │
│   │   ├── home/azureuser/   (your user files)            │   │
│   │   ├── opt/omis-pc/      (your application)           │   │
│   │   ├── var/log/          (logs)                       │   │
│   │   └── ...                                            │   │
│   │                                                      │   │
│   │   Ubuntu 22.04 Linux                                 │   │
│   │   50 GB Total                                        │   │
│   │                                                      │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### OS Disk Properties

| Property | What It Means | Our Value |
|----------|---------------|-----------|
| `disk_size_gb` | How big the disk is | 50 GB |
| `storage_account_type` | Performance tier | Standard_LRS |
| `caching` | Read/write caching | ReadWrite |

### Storage Types

| Type | Speed | Cost | Use Case |
|------|-------|------|----------|
| `Standard_LRS` | Slower (HDD) | Cheap | Dev, low I/O workloads |
| `StandardSSD_LRS` | Medium (SSD) | Medium | Most workloads |
| `Premium_LRS` | Fast (SSD) | Expensive | Databases, high I/O |

**In our repo** (`modules/azure/vm/main.tf`):
```hcl
os_disk {
  name                 = "${var.name}-osdisk"     # "omis-pc-prod-vm-osdisk"
  caching              = "ReadWrite"               # Cache reads and writes
  storage_account_type = var.os_disk_type          # "Standard_LRS"
  disk_size_gb         = var.os_disk_size_gb       # 50
}
```

### OS Disk vs Data Disk

| Type | Purpose | Survives VM Delete? |
|------|---------|---------------------|
| **OS Disk** | Operating system, boot | Usually deleted with VM |
| **Data Disk** | Application data, databases | Can be kept separately |

For our setup, we use the OS disk for everything since the database is managed separately by Azure.

---

## Part 9: What is ACR? (Azure Container Registry)

### First: What is Docker/Containers?

**The Problem Containers Solve**:

Your app needs:
- Node.js version 18
- Specific npm packages
- Certain environment variables
- Java 17 for csvtomdb
- PostgreSQL client libraries

On your laptop, it works. On a fresh VM, you'd need to install ALL of this.

**A Container = Your App + Everything It Needs, Packaged Together**

```
┌─────────────────────────────────────────────────────────────┐
│                    CONTAINER IMAGE                           │
│                 (Like a shipping container)                  │
│                                                              │
│   ┌─────────────────────────────────────────────────────┐   │
│   │  Your Application Code                               │   │
│   │  + Node.js runtime                                   │   │
│   │  + All npm dependencies                              │   │
│   │  + Configuration files                               │   │
│   │  + Everything needed to run                          │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                              │
│   Ship this ANYWHERE → It runs the same way                  │
└─────────────────────────────────────────────────────────────┘
```

**Analogy**:
- Without containers = Moving house by describing what you own
- With containers = Moving house by shipping the entire room

### ACR = Private Storage for Your Container Images

**Docker Hub** is a public registry (like GitHub for containers).
**ACR** is your PRIVATE registry.

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│   Developer's Laptop                Azure                    │
│   ─────────────────                 ─────                    │
│                                                              │
│   1. Build container    ────────►   2. Push to ACR           │
│      docker build                      (private storage)     │
│                                              │                │
│                                              │                │
│                                              ▼                │
│                                     3. VM pulls from ACR     │
│                                        docker pull           │
│                                              │                │
│                                              ▼                │
│                                     4. VM runs container     │
│                                        docker run            │
└─────────────────────────────────────────────────────────────┘
```

**Why private?**
- Your code is proprietary
- Security (no public access)
- Control over who can pull images

**In our repo** (`modules/azure/acr/main.tf`):
```hcl
resource "azurerm_container_registry" "this" {
  name                = var.name           # "omispcacrprod"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku            # "Standard"
  admin_enabled       = true               # Can login with password
}
```

The VM then pulls images like:
```bash
docker pull omispcacrprod.azurecr.io/omis-pc/fe:latest
docker pull omispcacrprod.azurecr.io/omis-pc/be:latest
docker pull omispcacrprod.azurecr.io/omis-pc/csvtomdb-service:latest
```

---

## Part 10: What is the Database Module?

### PostgreSQL Flexible Server

Your app stores data (users, products, configurations). That data lives in PostgreSQL.

**Why not run PostgreSQL on the VM?**

You could, but:
- YOU would manage backups
- YOU would handle updates/security patches
- YOU would configure replication
- If VM dies, database dies

**Azure Managed Database**:
- Azure handles backups automatically
- Azure patches security vulnerabilities
- Azure provides high availability
- Your data survives even if VM dies

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│   Your VM                          Azure Managed DB          │
│   ────────                         ────────────────          │
│                                                              │
│   ┌──────────┐                     ┌──────────────┐          │
│   │ Backend  │ ───── SQL ────────► │  PostgreSQL  │          │
│   │  App     │     Queries         │   Server     │          │
│   └──────────┘                     │              │          │
│                                    │  • Backups   │          │
│                                    │  • Patches   │          │
│                                    │  • Monitoring│          │
│                                    └──────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

**In our repo** (`modules/azure/database/main.tf`):
```hcl
resource "azurerm_postgresql_flexible_server" "this" {
  name                     = var.name              # "omis-pc-prod-db"
  administrator_login      = var.admin_username    # "omispcadmin"
  administrator_password   = var.admin_password    # (secret)
  sku_name                 = var.sku_name          # "B_Standard_B2ms"
  storage_mb               = var.storage_mb        # 65536 (64GB)
  backup_retention_days    = 14                    # Keep 14 days of backups
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = var.database_name    # "omis_pc_db"
  server_id = azurerm_postgresql_flexible_server.this.id
}
```

### Database Firewall Rules

The database has its OWN firewall (separate from NSG).

```
┌─────────────────────────────────────────────────────────────┐
│              DATABASE FIREWALL                               │
│                                                              │
│   Who can connect to the database?                           │
│                                                              │
│   ✅ Azure Services (internal Azure traffic)                 │
│   ✅ Your VM's IP (52.160.10.21)                             │
│   ❌ Everyone else: BLOCKED                                  │
│                                                              │
│   Even if a hacker knows the DB address,                     │
│   they can't connect because their IP isn't allowed.         │
└─────────────────────────────────────────────────────────────┘
```

```hcl
firewall_rules = [
  {
    name     = "AllowVM"
    start_ip = module.vm.public_ip    # Only VM can connect
    end_ip   = module.vm.public_ip
  }
]
```

---

## Part 11: What is the VM Module?

This is the actual computer that runs your application.

### Components Inside the VM Module

```
┌─────────────────────────────────────────────────────────────┐
│                    VM MODULE CREATES                         │
│                                                              │
│   1. Public IP (PIP) ──────► The address users reach you at  │
│                                                              │
│   2. NIC (Network Interface Card) ──────► Connects VM        │
│                                           to network         │
│                                                              │
│   3. Linux Virtual Machine ──────► The actual computer       │
│         • Ubuntu 22.04 OS                                    │
│         • 4 CPU cores, 16GB RAM                              │
│         • 50GB disk                                          │
│         • SSH key authentication                             │
│         • Cloud-init script (setup on first boot)            │
└─────────────────────────────────────────────────────────────┘
```

### The VM Resource

```hcl
resource "azurerm_linux_virtual_machine" "this" {
  name                = var.name              # "omis-pc-prod-vm"
  size                = var.size              # "Standard_D4ps_v5"
  admin_username      = var.admin_username    # "azureuser"

  # SSH key (no passwords!)
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  # Connect to network
  network_interface_ids = [azurerm_network_interface.this.id]

  # Disk
  os_disk {
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 50
  }

  # Operating System
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-arm64"           # Ubuntu 22.04 for ARM64
  }

  # Setup script
  custom_data = var.custom_data              # Cloud-init
}
```

### VM Sizes Explained

The size `Standard_D4ps_v5` means:
- **D** = General purpose (balanced CPU/memory)
- **4** = 4 vCPUs
- **p** = ARM64 processor (cheaper than Intel)
- **s** = Supports premium storage
- **v5** = Version 5 (latest generation)

| Size | vCPUs | RAM | Use Case |
|------|-------|-----|----------|
| Standard_B1s | 1 | 1 GB | Tiny dev/test |
| Standard_D2ps_v5 | 2 | 8 GB | Small production |
| Standard_D4ps_v5 | 4 | 16 GB | Medium production |
| Standard_D8ps_v5 | 8 | 32 GB | Large production |

---

## Part 12: What is Cloud-Init?

When a VM boots for the first time, it's a blank Ubuntu machine. Cloud-init is a script that sets it up.

**Analogy**: Cloud-init is like the setup wizard when you buy a new phone.

### What Our Cloud-Init Does

Located at `common/cloud-init-azure.yaml.tpl`:

```yaml
#cloud-config

# 1. Update system and install packages
package_update: true
package_upgrade: true

packages:
  - docker-ce              # Docker
  - git                    # Version control
  - vim                    # Text editor
  - htop                   # System monitor
  - curl                   # HTTP client
  - jq                     # JSON processor

# 2. Create user with SSH access
users:
  - name: azureuser
    groups: sudo, docker    # Can use sudo and docker
    ssh_authorized_keys:
      - ssh-rsa AAAA...     # Your public key

# 3. Setup firewall (iptables)
write_files:
  - path: /etc/iptables/rules.v4
    content: |
      # Allow ports 22, 80, 443, 3000, 5000, 5001
      # Block everything else

# 4. Create docker-compose file
  - path: /opt/omis-pc/docker-compose.yml
    content: |
      services:
        frontend:
          image: ${REGISTRY}/omis-pc/fe:latest
          ports:
            - "3000:3000"
        backend:
          image: ${REGISTRY}/omis-pc/be:latest
          ports:
            - "5000:5000"
            - "5001:5001"
        csvtomdb:
          image: ${REGISTRY}/omis-pc/csvtomdb-service:latest
          expose:
            - "8080"     # Internal only!

# 5. Create deployment script
  - path: /opt/omis-pc/deploy.sh
    content: |
      #!/bin/bash
      # Script to update and deploy services

# 6. Run commands on first boot
runcmd:
  - systemctl start docker
  - systemctl enable docker
```

After cloud-init runs, your VM is ready to run the application.

---

## Part 13: How It All Connects

The complete picture:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
│                                 │                                            │
│                    User types: http://52.160.10.21:3000                     │
│                                 │                                            │
│                                 ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         AZURE                                         │   │
│  │                                                                       │   │
│  │   ┌─────────────────────────────────────────────────────────────┐    │   │
│  │   │              RESOURCE GROUP: sazim-3dif-omis-pc-prod        │    │   │
│  │   │                                                              │    │   │
│  │   │   ┌──────────────────────────────────────────────────────┐  │    │   │
│  │   │   │              VNET: 10.2.0.0/16                        │  │    │   │
│  │   │   │                                                       │  │    │   │
│  │   │   │   ┌───────────────────────────────────────────────┐  │  │    │   │
│  │   │   │   │         SUBNET: 10.2.1.0/24                   │  │  │    │   │
│  │   │   │   │                    │                          │  │  │    │   │
│  │   │   │   │         ┌──────────┴──────────┐               │  │  │    │   │
│  │   │   │   │         │     NSG (Firewall)  │               │  │  │    │   │
│  │   │   │   │         │  ✅ 22,80,443,3000  │               │  │  │    │   │
│  │   │   │   │         │  ✅ 5000,5001       │               │  │  │    │   │
│  │   │   │   │         └──────────┬──────────┘               │  │  │    │   │
│  │   │   │   │                    │                          │  │  │    │   │
│  │   │   │   │         ┌──────────▼──────────┐               │  │  │    │   │
│  │   │   │   │         │   PUBLIC IP (PIP)   │               │  │  │    │   │
│  │   │   │   │         │   52.160.10.21      │               │  │  │    │   │
│  │   │   │   │         └──────────┬──────────┘               │  │  │    │   │
│  │   │   │   │                    │                          │  │  │    │   │
│  │   │   │   │         ┌──────────▼──────────┐               │  │  │    │   │
│  │   │   │   │         │   NIC (10.2.1.4)    │               │  │  │    │   │
│  │   │   │   │         └──────────┬──────────┘               │  │  │    │   │
│  │   │   │   │                    │                          │  │  │    │   │
│  │   │   │   │         ┌──────────▼──────────┐               │  │  │    │   │
│  │   │   │   │         │        VM           │               │  │  │    │   │
│  │   │   │   │         │  ┌──────────────┐   │               │  │  │    │   │
│  │   │   │   │         │  │   Docker     │   │               │  │  │    │   │
│  │   │   │   │         │  │  ┌────────┐  │   │               │  │  │    │   │
│  │   │   │   │         │  │  │Frontend│  │   │               │  │  │    │   │
│  │   │   │   │         │  │  │ :3000  │  │   │               │  │  │    │   │
│  │   │   │   │         │  │  ├────────┤  │   │               │  │  │    │   │
│  │   │   │   │         │  │  │Backend │  │   │               │  │  │    │   │
│  │   │   │   │         │  │  │:5000/01│  │   │               │  │  │    │   │
│  │   │   │   │         │  │  ├────────┤  │   │               │  │  │    │   │
│  │   │   │   │         │  │  │csvtomdb│  │   │               │  │  │    │   │
│  │   │   │   │         │  │  │ :8080  │  │   │               │  │  │    │   │
│  │   │   │   │         │  │  └────────┘  │   │               │  │  │    │   │
│  │   │   │   │         │  └──────────────┘   │               │  │  │    │   │
│  │   │   │   │         └─────────────────────┘               │  │  │    │   │
│  │   │   │   └───────────────────────────────────────────────┘  │  │    │   │
│  │   │   └──────────────────────────────────────────────────────┘  │    │   │
│  │   │                                                              │    │   │
│  │   │   ┌────────────────┐         ┌────────────────────┐         │    │   │
│  │   │   │      ACR       │         │    PostgreSQL DB   │         │    │   │
│  │   │   │ (Image Store)  │         │   omis_pc_db       │         │    │   │
│  │   │   │                │         │                    │         │    │   │
│  │   │   │ omispcacrprod  │         │ Firewall: VM only  │         │    │   │
│  │   │   └────────────────┘         └────────────────────┘         │    │   │
│  │   │                                                              │    │   │
│  │   └──────────────────────────────────────────────────────────────┘    │   │
│  └───────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 14: Why Modules?

You noticed we have `modules/azure/vm/`, `modules/azure/vnet/`, etc.

### The Problem Without Modules

Imagine you had to write ALL the code in one file:
- 500 lines of Terraform
- Hard to read
- Hard to reuse
- Easy to make mistakes

### Modules = Functions in Terraform

Just like in programming:

```javascript
// Without functions (bad)
// ... 500 lines of code all mixed together

// With functions (good)
function createUser() { ... }
function sendEmail() { ... }
function processPayment() { ... }
```

In Terraform:
```hcl
# Without modules (bad)
# ... 500 lines all mixed together

# With modules (good)
module "vnet" { ... }     # Create network
module "nsg" { ... }      # Create firewall
module "vm" { ... }       # Create computer
module "database" { ... } # Create database
```

### Benefits of Modules

| Benefit | Explanation |
|---------|-------------|
| **Reusable** | Use the same module for dev/staging/prod |
| **Readable** | Each module does ONE thing |
| **Testable** | Test modules independently |
| **Maintainable** | Change a module without affecting others |
| **Shareable** | Other teams can use your modules |

---

## Part 15: The Complete Terraform Flow

When you run `terraform apply`:

```
┌─────────────────────────────────────────────────────────────┐
│                     TERRAFORM APPLY                          │
│                                                              │
│   1. Read main.tf                                            │
│   2. Build dependency graph                                  │
│   3. Create in order:                                        │
│                                                              │
│      ┌──────────────────┐                                    │
│      │ Resource Group   │  ← First (container for all)       │
│      └────────┬─────────┘                                    │
│               │                                              │
│      ┌────────▼─────────┐                                    │
│      │      VNet        │  ← Network comes next              │
│      └────────┬─────────┘                                    │
│               │                                              │
│      ┌────────▼─────────┐                                    │
│      │    Subnet        │  ← Subdivision of network          │
│      └────────┬─────────┘                                    │
│               │                                              │
│      ┌────────▼─────────┐                                    │
│      │      NSG         │  ← Firewall rules                  │
│      └────────┬─────────┘                                    │
│               │                                              │
│      ┌────────▼─────────┐                                    │
│      │    Public IP     │  ← Internet address                │
│      └────────┬─────────┘                                    │
│               │                                              │
│      ┌────────▼─────────┐                                    │
│      │      NIC         │  ← Network card                    │
│      └────────┬─────────┘                                    │
│               │                                              │
│      ┌────────▼─────────┐                                    │
│      │       VM         │  ← The computer                    │
│      └────────┬─────────┘                                    │
│               │                                              │
│      ┌────────▼─────────┐                                    │
│      │ NSG Associations │  ← Attach firewall                 │
│      └────────┬─────────┘                                    │
│               │                                              │
│   ┌───────────┴───────────┐                                  │
│   │           │           │                                  │
│   ▼           ▼           ▼                                  │
│ ┌───┐     ┌───────┐   ┌────────────┐                        │
│ │ACR│     │  DB   │   │ DB Firewall│                        │
│ └───┘     └───────┘   └────────────┘                        │
│                                                              │
│   4. Save state (terraform.tfstate)                          │
│   5. Output connection info                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 16: Quick Reference - All Components

| Component | What It Is | Why We Need It |
|-----------|-----------|----------------|
| **Resource Group** | Folder for Azure resources | Organization, billing, permissions |
| **VNet** | Private network | Isolation from other customers |
| **Subnet** | Section of VNet | Different security zones |
| **NSG** | Firewall rules | Block unauthorized traffic |
| **PIP (Public IP)** | Internet address | Users can reach your app |
| **NIC** | Network card | Connect VM to network |
| **OS Disk** | Virtual hard drive | Store OS and files |
| **VM** | Virtual computer | Run your application |
| **Cloud-init** | Setup script | Install Docker, configure VM |
| **ACR** | Container storage | Store your Docker images privately |
| **PostgreSQL** | Managed database | Store data with automatic backups |
| **DB Firewall** | Database access rules | Only VM can connect to DB |

---

---

## Part 17: What is TLS/HTTPS and Why Do We Need It?

### The Problem: Unencrypted Communication

When you visit a website with `http://` (note: no 's'), your communication is **completely unencrypted**.

**Analogy**: Sending a postcard vs. a sealed envelope.

```
┌─────────────────────────────────────────────────────────────┐
│                  HTTP (Unencrypted)                          │
│                                                              │
│   You ───┬───┬───┬───┬───┬───► Server                       │
│          │   │   │   │   │                                   │
│      password  credit  API    Any point                      │
│       visible  card   token   in between                     │
│         here  number  here     can read                      │
│                                everything                     │
│                                                              │
│   Like shouting your password across a crowded room         │
└─────────────────────────────────────────────────────────────┘
```

**Anyone in the middle can:**
- Read your passwords
- Steal session tokens
- Modify the data
- Impersonate the server

### The Solution: TLS (Transport Layer Security)

TLS encrypts all communication between your browser and the server.

```
┌─────────────────────────────────────────────────────────────┐
│                  HTTPS (Encrypted with TLS)                  │
│                                                              │
│   You ─── [encrypted tunnel] ───► Server                    │
│          ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                                  │
│          Anyone intercepting                                 │
│          sees only gibberish                                 │
│          ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                                  │
│                                                              │
│   Like whispering in a soundproof booth                      │
└─────────────────────────────────────────────────────────────┘
```

### What TLS Actually Provides

| Feature | What It Means | Why It Matters |
|---------|---------------|----------------|
| **Encryption** | Data scrambled during transmission | Prevents eavesdropping |
| **Authentication** | Verify server identity | Prevents impersonation |
| **Integrity** | Detect if data was tampered with | Prevents modification |

### How TLS Works (Simplified)

```
┌─────────────────────────────────────────────────────────────┐
│                    TLS HANDSHAKE                             │
│                                                              │
│   1. User Browser ────────────────► Server                   │
│      "Hello, I want a secure connection"                     │
│                                                              │
│   2. User Browser ◄──────────────── Server                   │
│      "Here's my certificate to prove who I am"               │
│      (Certificate signed by trusted authority)               │
│                                                              │
│   3. User Browser ────────────────► Server                   │
│      "I verified your certificate, here's an                 │
│       encrypted key for our conversation"                    │
│                                                              │
│   4. ▓▓▓▓▓▓▓▓ All further communication encrypted ▓▓▓▓▓▓▓▓   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### What is a TLS Certificate?

A certificate is like a passport for your server.

```
┌─────────────────────────────────────────────────────────────┐
│                    TLS CERTIFICATE                           │
│                                                              │
│   Domain: omis-pc.example.com                                │
│   Owner: Your Organization                                   │
│   Valid From: 2025-01-01                                     │
│   Valid Until: 2025-04-01 (90 days for Let's Encrypt)       │
│   Issuer: Let's Encrypt Authority                            │
│   Signature: [cryptographic signature]                       │
│                                                              │
│   This signature proves the certificate is legitimate        │
└─────────────────────────────────────────────────────────────┘
```

**How browsers trust certificates:**

1. **Certificate Authorities (CAs)** are companies that verify identities
2. Browsers have a list of trusted CAs built-in
3. When a CA signs a certificate, browsers trust it
4. If certificate is invalid/expired, browser shows warning

**Popular CAs:**
- Let's Encrypt (Free, automated, used by Caddy)
- DigiCert
- Cloudflare
- GlobalSign

### HTTP vs HTTPS

| Feature | HTTP | HTTPS |
|---------|------|-------|
| **URL** | `http://example.com` | `https://example.com` |
| **Port** | 80 | 443 |
| **Encryption** | ❌ None | ✅ TLS encrypted |
| **Browser Indicator** | "Not Secure" warning | Green padlock 🔒 |
| **Data Visible To** | ISP, WiFi owner, anyone | Only you and server |
| **Passwords Safe** | ❌ Sent in plain text | ✅ Encrypted |
| **SEO Ranking** | Lower | Higher |
| **Modern Browser Features** | Limited | Full access |

### Our TLS Setup: Caddy Reverse Proxy

The infrastructure includes **Caddy**, which provides automatic HTTPS.

```
┌─────────────────────────────────────────────────────────────┐
│                   WITHOUT DOMAIN (Current)                   │
│                                                              │
│   User ─── HTTP ───► Caddy ─── HTTP ───► Services           │
│         (Port 80)        ▼                                   │
│                     No encryption                            │
│                     Just proxying                            │
│                                                              │
│   Access: http://20.245.121.120                              │
│   Status: ⚠️ Insecure (testing only)                         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   WITH DOMAIN (Future)                       │
│                                                              │
│   User ─── HTTPS ───► Caddy ─── HTTP ───► Services          │
│        (Port 443)        ▲                                   │
│        Encrypted    [TLS Magic]                              │
│                          ▼                                   │
│                   Let's Encrypt                              │
│                   Auto-renew certs                           │
│                                                              │
│   Access: https://omis-pc.example.com                        │
│   Status: ✅ Secure                                          │
└─────────────────────────────────────────────────────────────┘
```

### What Caddy Does Automatically

When you set a domain in the environment:

```bash
DOMAIN=omis-pc.example.com
```

Caddy automatically:
1. **Requests certificate** from Let's Encrypt
2. **Proves domain ownership** (HTTP-01 challenge)
3. **Installs certificate** in its storage
4. **Enables HTTPS** on port 443
5. **Redirects HTTP→HTTPS** automatically
6. **Renews certificate** 30 days before expiry (every 60 days)
7. **Adds security headers** (HSTS, X-Frame-Options, etc.)

**You don't need to:**
- Manually create certificates
- Configure HTTPS settings
- Remember to renew certificates
- Manage certificate storage

### WebSocket Security (WSS)

WebSockets also need encryption.

```
┌─────────────────────────────────────────────────────────────┐
│              WebSocket Protocols                             │
│                                                              │
│   ws://  ───► Unencrypted WebSocket (like HTTP)             │
│   wss:// ───► Encrypted WebSocket (like HTTPS)              │
│                                                              │
│   Without Domain:                                            │
│   ws://20.245.121.120:5001  ⚠️ Insecure                      │
│                                                              │
│   With Domain + TLS:                                         │
│   wss://omis-pc.example.com  ✅ Secure                       │
└─────────────────────────────────────────────────────────────┘
```

Caddy automatically upgrades WebSocket connections to WSS when HTTPS is enabled.

### Why You Don't Have TLS Yet

**You need a domain name to get a TLS certificate.**

```
┌─────────────────────────────────────────────────────────────┐
│            Why IP Addresses Can't Get Certificates          │
│                                                              │
│   ❌ Let's Encrypt: "20.245.121.120"                         │
│      → Cannot verify ownership of an IP                      │
│      → IPs can change or be reassigned                       │
│      → Certificate would be tied to infrastructure           │
│                                                              │
│   ✅ Let's Encrypt: "omis-pc.example.com"                    │
│      → Can verify via DNS                                    │
│      → Domain stays same even if IP changes                  │
│      → Certificate tied to your organization                 │
└─────────────────────────────────────────────────────────────┘
```

**Current state:**
- Infrastructure is HTTPS-ready ✅
- Caddy is configured ✅
- Just waiting for domain ⏳

**When you get a domain:**
1. Point DNS to `20.245.121.120`
2. Set `DOMAIN=your-domain.com` in `.env`
3. Restart containers
4. Caddy provisions certificate automatically
5. HTTPS works instantly

### Security Headers Explained

Caddy adds these security headers when HTTPS is enabled:

```
┌─────────────────────────────────────────────────────────────┐
│                   SECURITY HEADERS                           │
│                                                              │
│   Strict-Transport-Security (HSTS)                           │
│   → "Only connect via HTTPS for next 365 days"              │
│   → Prevents downgrade attacks                               │
│                                                              │
│   X-Content-Type-Options: nosniff                            │
│   → "Don't guess content types"                              │
│   → Prevents MIME-type confusion attacks                     │
│                                                              │
│   X-Frame-Options: DENY                                      │
│   → "Don't allow embedding in iframes"                       │
│   → Prevents clickjacking attacks                            │
│                                                              │
│   Referrer-Policy: strict-origin-when-cross-origin          │
│   → "Limit referrer information leakage"                     │
│   → Protects user privacy                                    │
└─────────────────────────────────────────────────────────────┘
```

### Common TLS Misconceptions

| Myth | Reality |
|------|---------|
| "HTTPS slows down websites" | Modern TLS has minimal overhead (~50ms) |
| "Only e-commerce needs HTTPS" | ALL websites should use HTTPS |
| "HTTPS is expensive" | Let's Encrypt provides FREE certificates |
| "Certificates are hard to manage" | Caddy automates everything |
| "Internal apps don't need HTTPS" | Attackers can be on your network |
| "My app has no sensitive data" | Session tokens, cookies, etc. are sensitive |

### When to Use HTTP (Answer: Almost Never)

**Acceptable:**
- Local development on `localhost`
- Completely isolated internal networks (no internet)
- Legacy systems being migrated

**NOT Acceptable:**
- Any internet-facing application
- Applications handling user data
- Production environments
- APIs accessed by mobile apps

### Monitoring Certificate Health

Even though Caddy auto-renews, you should monitor:

```bash
# Check certificate expiry date
echo | openssl s_client -connect omis-pc.example.com:443 2>/dev/null | \
  openssl x509 -noout -dates

# Expected output:
notBefore=Jan  1 00:00:00 2025 GMT
notAfter=Apr  1 00:00:00 2025 GMT  # 90 days from issuance
```

**Certificate Lifecycle Visualization:**

```
┌─────────────────────────────────────────────────────────────┐
│           CERTIFICATE LIFECYCLE (90-day validity)            │
│                                                              │
│   Day 0                                                      │
│   ┌────────────────────────────────────────────────┐        │
│   │ ✅ Certificate Issued by Let's Encrypt          │        │
│   │    Valid for 90 days                            │        │
│   └────────────────────────────────────────────────┘        │
│   │                                                          │
│   ├─► Days 1-59: Certificate valid, everything works        │
│   │   ┌──────────────────────────────────┐                  │
│   │   │ 🔒 HTTPS working normally         │                  │
│   │   │ 🔄 Caddy monitoring expiry date   │                  │
│   │   └──────────────────────────────────┘                  │
│   │                                                          │
│   Day 60 (30 days before expiry)                             │
│   ┌────────────────────────────────────────────────┐        │
│   │ 🔄 Caddy: "Time to renew!"                      │        │
│   │    → Contacts Let's Encrypt                     │        │
│   │    → Completes challenge                        │        │
│   │    → Downloads new certificate                  │        │
│   │    → Swaps to new cert (zero downtime)          │        │
│   └────────────────────────────────────────────────┘        │
│   │                                                          │
│   │   If renewal fails:                                      │
│   ├─► Day 61: Retry #1                                       │
│   ├─► Day 62: Retry #2                                       │
│   ├─► Day 63: Retry #3                                       │
│   │   ... continues retrying daily ...                       │
│   │                                                          │
│   Day 90 (expiry day)                                        │
│   ┌────────────────────────────────────────────────┐        │
│   │ ⚠️ If all renewals failed:                      │        │
│   │    Certificate EXPIRES                          │        │
│   │    → Browser shows security warning             │        │
│   │    → Users can't access site securely           │        │
│   │    → Manual intervention required               │        │
│   └────────────────────────────────────────────────┘        │
│                                                              │
│   🎯 Renewal Strategy:                                       │
│   • Attempt at day 60 (30-day safety buffer)                │
│   • Retry daily if failed (30 chances to fix issues)        │
│   • Logs all attempts to docker logs                        │
│   • No manual intervention needed (usually)                 │
└─────────────────────────────────────────────────────────────┘
```

**Renewal timeline:**
- **Day 0:** Certificate issued (90-day validity)
- **Days 1-59:** ✅ Active use, no action needed
- **Day 60:** 🔄 Caddy attempts first renewal automatically
- **Days 61-89:** 🔄 Caddy retries daily if renewal failed
- **Day 90:** ⚠️ Certificate expires (if all renewals failed)

**Caddy renews at day 60, giving 30 days buffer for any issues.**

---

## Summary

You now understand:

1. **What a computer is** - CPU, RAM, Disk, NIC
2. **What networking is** - IPs, Ports, Private vs Public
3. **What each Azure component does**:
   - **VNet** = Your private network
   - **Subnet** = Divisions within the network
   - **NSG** = Firewall rules
   - **PIP** = Your internet address
   - **NIC** = Network connector
   - **OS Disk** = Virtual hard drive
   - **VM** = Your computer
   - **ACR** = Docker image storage
   - **PostgreSQL** = Managed database
4. **Why we use Terraform** - Reproducible, version-controlled infrastructure
5. **Why we use modules** - Reusable, maintainable code
6. **What TLS/HTTPS is** - Encryption, authentication, and integrity for web traffic
7. **How Caddy provides automatic HTTPS** - Zero-config certificate management

This knowledge applies to ANY cloud provider (AWS, GCP, etc.) - the concepts are the same, just different names.

---

**Next Steps**: 
- See [DEPLOYMENT_WORKFLOW.md](./DEPLOYMENT_WORKFLOW.md) for deploying the application
- See [TLS_SETUP_GUIDE.md](./TLS_SETUP_GUIDE.md) for enabling HTTPS when you get a domain
