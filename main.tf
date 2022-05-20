# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }
  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

local {
    location = "eastus1"
    prefix = "team4"
}

resource "azurerm_resource_group" "this" {
  name     = "${local.prefix}-rg"
  location = local.location
}



resource "azurerm_virtual_network" "this" {
  name                = "${local.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.2.0/24"]
}


resource "azurerm_network_interface" "this" {
  name                = "${local.prefix}-nic"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_ssh_public_key" "this" {
  name                = "this"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  public_key          = file("files/.ssh/id_rsa.pub")
}

resource "azurerm_orchestrated_virtual_machine_scale_set" "this" {
  name                = "${local.prefix}-OVMSS"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  sku_name  = "Standard_F2"
  instances = 3

  platform_fault_domain_count = 2

  os_profile {
    linux_configuration {
      computer_name_prefix = local.prefix
      admin_username       = "clippy"

      admin_ssh_key {
        username   = "clippy"
        public_key = azurerm_ssh_public_key.this.public_key
      }
      admin_ssh_key {
        username   = "clippy"
        public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDFg1CAiEqYi8Yf0t9ZOASYIfrtkDF9K0Mz1fEUm9zxWPISwlRBOjMyWI/03YXJxMrZNJgNOCxEA4TI7VOn7fap5Fj8Kd/2/cQggELKFF0+25+3Sdm6JnzPpluRx3/yTWSuKNStpmFsaUu2v+4T6oDHB9pQ3Cr3zUaLc99Ib9FCoIHdMVIW2vdEu1UfgiHIdqi1o4TPVc5vLZOJzvDd69TUI//mLihjkfUVR35YgGkhJVMUFqFj4EgYGR9zsdVqfNHPSmrx69V2qwxLRB1wW4lcMbLQvKO5Blt2cmWd62KqxrL8kenxdG4/tD8qSyXY7VTTFSZuF0Uhx/riYIMHdbjfcIuOzhXETBUpyumMcqIs4Piirp0QeufYoMfV7ZKVle5wOhnFaAzTZRXlxByxAuWyYtR9H0yXO1j9yUE5mD7MxYmwLkA6KEHvEsbKC7KdgfyblSmgp0aXlf1HiX7vZvHJxtu89dU0jLpi1/0ddgK1m+FzfiesaOGdi8dLNkfmsh0= jphillips@kryzen"
      }
      admin_ssh_key {
        username   = "clippy"
        public_key = 
      }
    }
  }

  network_interface {
    name    = "${local.prefix}-NetworkProfile"
    primary = true

    ip_configuration {
      name      = "PrimaryIPConfiguration"
      primary   = true
      subnet_id = azurerm_subnet.internal.id

      public_ip_address {
        name                    = "${local.prefix}-PublicIpConfiguration"
        domain_name_label       = "${local.prefix}-domain-label"
        idle_timeout_in_minutes = 4
      }
    }
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "20.04-LTS"
    version   = "latest"
  }

  extension {
    name                               = "${local.prefix}-HealthExtension"
    publisher                          = "Microsoft.ManagedServices"
    type                               = "ApplicationHealthLinux"
    type_handler_version               = "1.0"
    auto_upgrade_minor_version_enabled = true

    settings = jsonencode({
      "protocol"    = "http"
      "port"        = 80
      "requestPath" = "/healthEndpoint"
    },
    {
      "protocol"    = "https"
      "port"        = 443
      "requestPath" = "/healthEndpoint"
    })
  }
}
