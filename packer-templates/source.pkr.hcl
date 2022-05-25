source "azure-arm" "rke2-base" {
  subscription_id = var.shared_gallery_subscription_id

  shared_image_gallery_destination {
    subscription   = var.shared_gallery_subscription_id
    resource_group = var.shared_gallery_resource_group_name
    gallery_name   = var.shared_gallery_name
    image_name     = var.shared_gallery_image_name
    image_version  = var.shared_gallery_image_version
    replication_regions = ["East US"]
    storage_account_type = "Standard_LRS"
  }

  managed_image_name                = var.managed_image_name
  managed_image_resource_group_name = var.managed_resource_group

  os_type         = "Windows"
  image_publisher = "MicrosoftWindowsServer"
  image_offer     = "WindowsServer"
  image_sku       = "2022-Datacenter"

  azure_tags = var.tags

  communicator   = "winrm"
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = "3m"
  winrm_username = "packer"

  location = var.location
  vm_size  = var.vm_size
}

build {
  sources = ["sources.azure-arm.rke2-base"]

  provisioner "powershell" {
    pause_before = "3m"
    elevated_user = "SYSTEM"
    elevated_password = ""
    inline = [
      "Install-WindowsFeature -Name Containers",
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"
    ]
  }

  provisioner "powershell" {
    inline = [
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
      "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    ]
  }

  provisioner "windows-restart" {
    pause_before          = "10s"
    restart_check_command = "powershell -command \"& {Write-Output 'restarted.'}\""
  }

  provisioner "windows-update" {
    search_criteria = "IsInstalled=0"
    filters = [
      "exclude:$_.Title -like '*Preview*'",
      "include:$true",
    ]
  }

  provisioner "windows-restart" {
    pause_before          = "10s"
    restart_check_command = "powershell -command \"& {Write-Output 'restarted.'}\""
    restart_timeout       = "10m"
  }

  provisioner "powershell" {
    inline = [
      "choco install vim -y"
    ]
  }

  provisioner "powershell" {
    inline = [
      "Set-Service -Name sshd -StartupType 'Automatic'",
      "Start-Service sshd",
      "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\OpenSSH' -Name DefaultShell -Value 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe' -PropertyType String -Force",
      "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name Shell -Value 'PowerShell.exe -NoExit'"
    ]
  }


  provisioner "powershell" {
    inline = [
      " # NOTE: the following *3* lines are only needed if the you have installed the Guest Agent.",
      "  while ((Get-Service RdAgent).Status -ne 'Running') { Start-Sleep -s 5 }",      
      "  while ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running') { Start-Sleep -s 5 }",

      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm",
      "while($true) { $imageState = Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State | Select ImageState; if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Write-Output $imageState.ImageState; Start-Sleep -s 10  } else { break } }"
    ]
  }
}


