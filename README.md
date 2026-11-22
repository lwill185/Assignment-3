# Charter School Azure Network – Terraform

Terraform starter implementation for a small charter school in Ann Arbor, Michigan. It deploys one Azure VNet in North Central US, external and internal workload subnets, Azure Firewall Basic, an Azure VPN Gateway for site-to-site IPsec, and eight virtual machines.

## Architecture

- Region: `northcentralus` (Chicago area; verify service and SKU availability for your subscription before deployment).
- VNet: `10.20.0.0/16`
- External workload subnet: `10.20.1.0/24` (two Ubuntu VMs with public IPs)
- Internal workload subnet: `10.20.2.0/24` (four Windows VMs and two private Ubuntu VMs)
- `AzureFirewallSubnet`: `10.20.3.0/26` (required Azure Firewall subnet)
- `GatewaySubnet`: `10.20.4.0/27` (required Azure VPN Gateway subnet)
- Windows VMs: four `Standard_F4s_v2` (4 vCPU, 8 GiB RAM)
- Linux VMs: four `Standard_F2s_v2` (2 vCPU, 4 GiB RAM)

### Network design note

Azure VPN Gateway is the IPsec endpoint. Azure Firewall is a separate managed firewall for policy enforcement and inspection. The tunnel does **not** terminate on Azure Firewall. If the school requires a firewall appliance itself to terminate IPsec, replace the managed VPN Gateway design with a supported third-party network virtual appliance (NVA) and its vendor-specific Terraform configuration.

The external subnet is not automatically a DMZ firewall. The two external Linux VMs have public IPs; their subnet NSG permits TCP 80/443 from the Internet and SSH only from `admin_source_cidr`. Replace the documentation-only default CIDR before applying. Do not expose SSH to `0.0.0.0/0`.

The internal subnet has no public IPs. RDP and SSH are permitted only from the configured on-premises CIDR ranges. Internal-subnet default internet traffic and configured on-premises traffic are routed through Azure Firewall. A route table on `GatewaySubnet` sends VPN-arriving traffic for the internal subnet through the firewall; a route table on the internal subnet sends the school's configured CIDRs back through the firewall. Gateway route propagation remains enabled on `GatewaySubnet`; the internal route table disables propagation and installs explicit school-prefix routes. The firewall policy contains baseline outbound DNS/web rules and a narrow set of common AD DS, NPS, and management ports from the school network. Review and reduce/extend these rules to match the school's actual requirements before production use.

## Prerequisites

1. An Azure subscription with permissions to create resource groups, networking, public IPs, firewalls, VPN gateways, and virtual machines.
2. Azure CLI logged in (`az login`) and selected subscription (`az account set --subscription <SUBSCRIPTION_ID>`).
3. Terraform 1.6 or later.
4. A public IP address for the school's VPN peer, its on-premises LAN CIDRs, a long random IPsec pre-shared key, an administrator public IP/CIDR, a Windows local administrator password, and an SSH public key.
5. Confirm regional quota and availability for `Standard_F4s_v2`, `Standard_F2s_v2`, Azure Firewall Basic, and `VpnGw1` in `northcentralus`. VM SKUs and service availability are subscription- and region-dependent.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with real values. Never commit this file.
az login
az account set --subscription <SUBSCRIPTION_ID>
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out charter-school.tfplan
terraform apply charter-school.tfplan
```

You can also provide sensitive values through environment variables rather than storing them in a tfvars file, for example `TF_VAR_windows_admin_password` and `TF_VAR_vpn_shared_key`. Terraform state can contain secrets and credentials. Use a secured remote Azure Storage backend with state locking, encryption, restricted RBAC, and versioning for team use. The example intentionally does not configure a backend because the storage account and access controls should be created in a separately secured bootstrap step.

## After deployment – required configuration

Terraform provisions the eight operating-system instances and network resources. It does **not** automatically promote domain controllers or configure enterprise PKI/RADIUS. Complete and test these steps through a controlled configuration-management process:

1. Configure `DC01` as the first AD DS forest/domain controller and DNS server; create the forest using the school's approved internal DNS domain.
2. Join `DC02` to the domain, promote it as an additional domain controller, and verify AD replication and DNS health.
3. Configure `MSCA01` as an Enterprise or Standalone CA according to the PKI design. Keep the CA private, back up its private key and CA database, and define certificate templates and revocation publication.
4. Join `NPS01` to the domain, install NPS, register it in Active Directory, configure RADIUS clients and policies, and test with pilot devices.
5. Configure Linux services, host firewalls, logging, monitoring, patching, backup, and vulnerability management.
6. Coordinate IKE/IPsec parameters, traffic selectors, routes, and failover testing with the school's VPN administrator. The local gateway resource uses the supplied peer IP and LAN prefixes.
7. Test from both directions: school-to-cloud DNS/AD/RADIUS/application access and authorized cloud-to-school access. Verify that public systems cannot reach management ports except from the specified administrator CIDR.

## Important security and operational notes

- This is a single-region, single-VNet baseline, not a highly available design. The two DCs provide directory redundancy, but the design has no zone-redundant VM placement or second VPN tunnel.
- Azure Firewall Basic and VPN Gateway have ongoing hourly and data-processing charges. Review current Azure pricing before deployment. VM, disk, public IP, bandwidth, and backup costs are additional.
- The Azure Firewall policy is a starter policy, not a complete production policy. It permits selected school-to-internal identity/authentication ports and a limited internal-to-school set for DNS, NTP, and RADIUS. Expand only where a documented application requirement exists, and add only required outbound destinations and ports.
- The external Linux hosts are Internet-addressable. Install only intended services and use host-based firewalling, automatic security updates, monitoring, and vulnerability scanning.
- Use Azure Bastion or a VPN-based administrative jump host for Windows RDP in a production design. Do not add public IPs to domain controllers, CA, NPS, or internal Linux hosts.
- Use Key Vault or another approved secret manager and a remote Terraform state backend. Do not commit secrets, private keys, state files, or plan files.
- Review school/student data handling, retention, FERPA obligations, and backup recovery requirements before production use.

## Files

- `versions.tf`: Terraform and provider requirements.
- `variables.tf`: configurable inputs.
- `main.tf`: network, firewall, VPN, NSGs, and VM resources.
- `outputs.tf`: useful deployment outputs.
- `terraform.tfvars.example`: sample input file (contains placeholders only).

## Destroy lab resources

After confirming that no school services depend on this environment:

```bash
terraform destroy
```

Do not run destroy against production without an approved change and recovery plan.
