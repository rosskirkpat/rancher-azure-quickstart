# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    rancher2 = {
      source = "rancher/rancher2"
    }
    template = {
      source = "hashicorp/template"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "azurerm" {
   features {}
}

# common
resource "random_integer" "this" {
  min = 1
  max = 9999
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
    location = "eastus"
    prefix = "team4-${random_integer.this.result}"
    public_ssh_key = "${tls_private_key.this.public_key_openssh}"
}

data "http" "myipv4" {
  url = "http://whatismyip.akamai.com/"
}

# base 
resource "azurerm_resource_group" "this" {
  name     = "${local.prefix}-rg"
  location = local.location
}

resource "azurerm_virtual_network" "this" {
  name                   = "${local.prefix}-vnet"
  address_space          = ["10.0.0.0/16"]
  location               = azurerm_resource_group.this.location
  resource_group_name    = azurerm_resource_group.this.name
}

resource "azurerm_subnet" "rancher" {
  name = "${local.prefix}-rancher-subnet"
  resource_group_name    = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes = [ "10.0.10.0/24" ]
}

resource "azurerm_subnet" "bastion" {
  name = "AzureBastionSubnet"
  resource_group_name    = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes = [ "192.168.1.224/27" ]
}

resource "azurerm_ssh_public_key" "this" {
  name                = "${local.prefix}-ssh-key"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  public_key          = tls_private_key.this.public_key_openssh
}

resource "local_sensitive_file" "rancher_pem_file" {
  filename = format("%s/%s", "${path.root}/keys", "${azurerm_ssh_public_key.this.name}.pem") 
  content = tls_private_key.this.private_key_pem
}

resource "azuread_service_principal" "team4_ad" {
  application_id = "81852a25-ec2a-4360-b498-e3137ef41556" 
}

# bastion for private network
resource "azurerm_public_ip" "bastion" {
  name                = "${local.prefix}-bastion-public-ip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "rancher" {
  name                = "${local.prefix}-bastion"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tunneling_enabled = true
  ip_connect_enabled = true
  sku = "Standard"


  ip_configuration {
    name                 = "${local.prefix}-bastion-network"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}


# Rancher NSGs
resource "azurerm_network_security_group" "rancher" {
  name                = "${local.prefix}-rancher-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "DenyAll"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix     = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "https"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes      = [azurerm_virtual_network.this.address_space[0], "${chomp(data.http.myipv4.body)}/32"]
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "http"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "etcd"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2379-2380"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }

    security_rule {
    name                       = "etcd-client"
    priority                   = 104
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2376"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }

    security_rule {
    name                       = "kube-api"
    priority                   = 105
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }

    security_rule {
    name                       = "windows-vxlan"
    priority                   = 106
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "8472"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "default-vxlan"
    priority                   = 107
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "4789"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "typha"
    priority                   = 108
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5473"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "kubelet"
    priority                   = 109
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "10250-10252"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "rke2-proxy"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9345"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "k8s-tcp-node-ports"
    priority                   = 111
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "k8s-udp-node-ports"
    priority                   = 112
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "bgp"
    priority                   = 113
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "179"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "prometheus-metrics"
    priority                   = 114
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9796"
    source_address_prefixes    = azurerm_virtual_network.this.address_space
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "inbound-frontdoor-https"
    priority                   = 115
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Frontdoor"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "inbound-frontdoor-http"
    priority                   = 116
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Frontdoor"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "OutboundAll"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "rancher" {
  subnet_id                 = azurerm_subnet.rancher.id
  network_security_group_id = azurerm_network_security_group.rancher.id
}

resource "azurerm_network_security_group" "mgmt" {
  name                = "${local.prefix}-mgmt-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowSyncWithAzureAD"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureActiveDirectoryDomainServices"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowRD"
    priority                   = 201
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowPSRemoting"
    priority                   = 301
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = "AzureActiveDirectoryDomainServices"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowLDAPS"
    priority                   = 401
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "636"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.rancher.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

resource "azuread_group" "dc_admins" {
  display_name     = "${local.prefix} AAD DC Administrators"
  security_enabled = true
}

resource "random_password" "aad_admin" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "azuread_user" "admin" {
  user_principal_name = "${local.prefix}-dc-admin@rancherlabs.work"
  display_name        = "${local.prefix} DC Administrator"
  password            = random_password.aad_admin.result
  disable_password_expiration = true
  account_enabled = true 
  force_password_change = false
}

resource "azuread_group_member" "admin" {
  group_object_id  = azuread_group.dc_admins.object_id
  member_object_id = azuread_user.admin.object_id
}

resource "azurerm_active_directory_domain_service" "this" {
  name                = "${local.prefix}-aaads"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  domain_name           = "rancherlabs.work"
  sku                   = "Enterprise"
  filtered_sync_enabled = false

  initial_replica_set {
    subnet_id                 = azurerm_subnet.rancher.id
  }

  notifications {
    additional_recipients = ["ross.kirkpatrick@suse.com", "jamie.phillips@suse.com"]
    notify_dc_admins      = true
    notify_global_admins  = true
  }

  security {
    sync_kerberos_passwords = true
    sync_ntlm_passwords     = true
    sync_on_prem_passwords  = true
  }

  tags = {
    Environment = "dev"
    RancherTeam = local.prefix
  }

  depends_on = [
    azuread_service_principal.team4_ad,
    azurerm_subnet_network_security_group_association.mgmt,
  ]
}

resource "random_password" "postgres_admin" {
  length           = 16
  special          = true
  override_special = "_%@"
}

# k3s external db for Rancher
resource "azurerm_postgresql_server" "this" {
  name                = "${local.prefix}-postgresql-server"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  sku_name = "B_Gen5_2"

  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = true

  administrator_login          = "psqladmin"
  administrator_login_password = random_password.postgres_admin.result 
  version                      = "9.5"
  ssl_enforcement_enabled      = true
  tags = {
    RancherTeam = local.prefix
    Environment = "dev"
  }
}

resource "azurerm_postgresql_database" "this" {
  name                = "${local.prefix}-postgresql-db"
  resource_group_name = azurerm_resource_group.this.name
  server_name         = azurerm_postgresql_server.this.name
  charset             = "UTF8"
  collation           = "English_United States.1252"
}

resource "azurerm_network_interface" "k3s_server" {
  name                = "${local.prefix}-k3s-server-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "k3s-server"
    subnet_id                     = azurerm_subnet.rancher.id
    private_ip_address_allocation = "Static"
  }
}

# rancher k3s server  (control-plane)
resource "azurerm_linux_virtual_machine" "rancher_server" {
  name                = "${local.prefix}-rancher-k3s-server"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = "Standard_F2"
  admin_username      = "rancher"
  network_interface_ids = [ azurerm_network_interface.k3s_server.id ]

  admin_ssh_key {
    username   = "rancher"
    public_key = azurerm_ssh_public_key.this.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "20.04-LTS"
    version   = "latest"
  }

  tags = {
    RancherTeam = local.prefix
    Environment = "dev"
  }
}

resource "azurerm_network_interface" "k3s_agent" {
  name                = "${local.prefix}-k3s-agent-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "k3s-agent"
    subnet_id                     = azurerm_subnet.rancher.id
    private_ip_address_allocation = "Static"
  }
}

# rancher k3s agent (worker)
resource "azurerm_linux_virtual_machine" "rancher_agent" {
  name                = "${local.prefix}-rancher-k3s-agent"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = "Standard_F2"
  admin_username      = "rancher"
  network_interface_ids = [ azurerm_network_interface.k3s_agent.id ]


  admin_ssh_key {
    username   = "rancher"
    public_key = azurerm_ssh_public_key.this.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "20.04-LTS"
    version   = "latest"
  }

  tags = {
    RancherTeam = local.prefix
    Environment = "dev"
  }
}

# downstream control-plane
resource "azurerm_linux_virtual_machine_scale_set" "control_plane" {
  name                = "${local.prefix}-ds-cp-vmss"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard_F2"
  instances           = 3
  admin_username      = "rancher"
  upgrade_mode = "Manual"

  admin_ssh_key {
    username   = "rancher"
    public_key = azurerm_ssh_public_key.this.public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "20.04-LTS"
    version   = "latest"
  }

  network_interface {
    name    = "ds_controlplane"
    primary = true

    ip_configuration {
      name      = "ds_controlplane"
      primary   = true
      subnet_id = azurerm_subnet.rancher.id
    }
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
    disk_size_gb = 40
  }

  tags = {
    RancherTeam = local.prefix
    Environment = "dev"
  }
}


# downstream etcd
resource "azurerm_linux_virtual_machine_scale_set" "etcd" {
  name                = "${local.prefix}-ds-etcd-vmss"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard_F2"
  instances           = 3
  admin_username      = "rancher"
  upgrade_mode = "Manual"

  admin_ssh_key {
    username   = "rancher"
    public_key = azurerm_ssh_public_key.this.public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "20.04-LTS"
    version   = "latest"
  }

  network_interface {
    name    = "ds_etcd"
    primary = true

    ip_configuration {
      name      = "ds_etcd"
      primary   = true
      subnet_id = azurerm_subnet.rancher.id
    }
  }

  os_disk {
    storage_account_type = "StandardSSD_LRS"
    caching              = "ReadWrite"
    disk_size_gb = 40
  }
  
  tags = {
    RancherTeam = local.prefix
    Environment = "dev"
  }
}


# downstream linux workers
resource "azurerm_linux_virtual_machine_scale_set" "linux_worker" {
  name                = "${local.prefix}-ds-linux-worker-vmss"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard_F2"
  instances           = 3
  admin_username      = "rancher"
  upgrade_mode = "Manual"

  admin_ssh_key {
    username   = "rancher"
    public_key = azurerm_ssh_public_key.this.public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "20.04-LTS"
    version   = "latest"
  }

  network_interface {
    name    = "ds_linux_worker"
    primary = true

    ip_configuration {
      name      = "ds_linux_worker"
      primary   = true
      subnet_id = azurerm_subnet.rancher.id
    }
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
    disk_size_gb = 50
  }

  tags = {
    RancherTeam = local.prefix
    Environment = "dev"
  }
}

resource "random_password" "windows_admin" {
  length           = 16
  special          = true
  override_special = "_%@"
}

# downstream windows
resource "azurerm_windows_virtual_machine_scale_set" "windows_worker" {
  name                = "${local.prefix}-ds-windows-worker-vmss"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard_F2"
  instances           = 3
  admin_password      = random_password.windows_admin.result 
  admin_username      = "rancher"
  upgrade_mode = "Manual"

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter-Server-Core"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
    disk_size_gb = 75
  }

  network_interface {
    name    = "ds_windows_worker"
    primary = true

    ip_configuration {
      name      = "ds_windows_worker"
      primary   = true
      subnet_id = azurerm_subnet.rancher.id
    }
  }

  tags = {
    RancherTeam = local.prefix
    Environment = "dev"
  }
}


output "aadds_domain_name" {
  value = azurerm_active_directory_domain_service.this.domain_name
}

output "aad_admin_user_password" {
  value = azuread_user.admin.password
  sensitive = true
}

output "aad_admin_user_principal_name" {
  value = azuread_user.admin.user_principal_name
}

output "bastion_network_config" {
  value = [azurerm_bastion_host.rancher.ip_configuration]
}

output "bastion_dns_name" {
  value = azurerm_bastion_host.rancher.dns_name
}

output "postgres_server_name" {
  value = azurerm_postgresql_database.this.server_name
}

output "postgres_admin_username" {
  value = azurerm_postgresql_server.this.administrator_login
}

output "postgres_admin_password" {
  value = azurerm_postgresql_server.this.administrator_login_password
  sensitive = true
}

output "postgres_server_fqdn" {
  value = azurerm_postgresql_server.this.fqdn
}

output "rancher_k3s_server_ip" {
  value = azurerm_linux_virtual_machine.rancher_server.private_ip_address
}

output "rancher_k3s_agent_ip" {
  value = azurerm_linux_virtual_machine.rancher_agent.private_ip_address
}

output "ds_windows_worker_ip" {
  value = [azurerm_windows_virtual_machine_scale_set.windows_worker[*].network_interface]
}

output "ds_windows_password" {
  value = azurerm_windows_virtual_machine_scale_set.windows_worker.admin_password
  sensitive = true
}

output "ds_etcd_ip" {
  value = [azurerm_linux_virtual_machine_scale_set.etcd[*].network_interface]
}

output "ds_cp_ip" {
  value = [azurerm_linux_virtual_machine_scale_set.control_plane[*].network_interface]
}

output "ds_linux_worker_ip" {
  value = [azurerm_linux_virtual_machine_scale_set.linux_worker[*].network_interface]
}