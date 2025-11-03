# Virtual Network Peering (3 Regions) + Private DNS Zone

> Deploy 3 virtual networks across different Azure regions, peer them together, and enable internal name resolution using a private DNS zone — all with Terraform!

---

## What does this project do?

This Terraform code automatically creates:

- **3 Resource Groups** in 3 Azure regions:  
  → `France Central`, `East US`, `Central India`
- **3 Virtual Networks (VNet)** with custom IP ranges:
  - France: `10.0.0.0/16`
  - US: `192.168.0.0/16`
  - India: `172.16.0.0/16`
- Each VNet has:
  - A **public subnet** (with RDP/HTTP access from internet)
  - A **private subnet** (no direct internet access)
- **Network Security Groups (NSG)**:
  - Public subnets: Allow RDP (3389) and HTTP (80)
  - Private subnets: No rules needed (default allows VNet-to-VNet traffic)
- **Full Mesh VNet Peering**: All 3 VNets can talk to each other.
- **Private DNS Zone** (`paul.lab`) hosted in France RG.
  - Links to all 3 VNets → VMs can resolve names like `apache2-us.paul.lab`
- **Virtual Machines**:
  - 🐧 **Linux (Ubuntu)** in *private* subnet → runs Apache2  
    → Page shows: `Hello, welcome to apache2-france (IP: 10.0.1.x)`
  - 🪟 **Windows (Server 2022)** in *public* subnet → runs IIS (Spot VM to save cost)  
    → Page shows: `Hello, Welcome to france-public!`
- **DNS A Records** for all VMs → use names instead of IPs!

---

## Architecture Overview

`3VnetPeering.svg`


---

## How to Deploy with Terraform

### Prerequisites

- Azure account with active subscription
- [Terraform installed](https://developer.hashicorp.com/terraform/downloads)
- Logged into Azure CLI:  
  ```bash
  az login

# 1. Clone or download this repo
git clone https://github.com/yourusername/your-repo-name.git
cd your-repo-name

# 2. Initialize Terraform (downloads Azure provider)
terraform init

# 3. Preview what will be created
terraform plan

# 4. Deploy everything!
terraform apply